import AppKit
import SwiftUI

/// Where a cover sits in Cover Flow, from its distance to the centre: the centre faces forward, the others
/// turn towards it, with a clear gap after the centre and the rest packed like a fanned stack.
struct CoverFlowGeometry: Equatable {
    var x: CGFloat
    /// Degrees about the vertical axis.
    var rotation: Double
    var scale: CGFloat
    var zIndex: Double
    /// Side covers sit a little darker, for depth.
    var brightness: Double

    /// How many covers either side of the centre can be seen.
    static let reach = 6
    /// How many are views: two more than can be seen, so covers join and leave beyond the stage's edges and
    /// only ever slide and turn into place, never fade in where you can see them.
    static let drawReach = reach + 2

    /// The centre cover's side for each element Size: larger than tiles, since Cover Flow is a showpiece.
    static func side(for size: ElementAppearance.Size) -> CGFloat {
        switch size {
        case .small: 180
        case .medium: 240
        case .large: 320
        }
    }

    /// How far apart side covers sit, as a fraction of the cover's side, for the element's Spacing.
    static func spread(for spacing: ElementAppearance.Spacing) -> CGFloat {
        switch spacing {
        case .compact: 0.2
        case .regular: 0.28
        case .roomy: 0.4
        }
    }

    /// The stage's height for a cover side: perspective makes a turned cover's near edge taller than the cover,
    /// so it needs room above and below or its corners are cropped.
    static func stageHeight(side: CGFloat) -> CGFloat { side * 1.5 }

    static func place(distance d: Int, side: CGFloat, spread: CGFloat = 0.28) -> CoverFlowGeometry {
        guard d != 0 else { return CoverFlowGeometry(x: 0, rotation: 0, scale: 1.08, zIndex: 100, brightness: 0) }
        let sign: CGFloat = d < 0 ? -1 : 1
        let steps = CGFloat(abs(d))
        return CoverFlowGeometry(x: sign * (side * (0.34 + spread) + (steps - 1) * side * spread),
                                 rotation: d < 0 ? 60 : -60, scale: 1, zIndex: 100 - Double(abs(d)),
                                 brightness: -min(0.08 + 0.03 * Double(abs(d)), 0.25))
    }

    static func isVisible(distance d: Int) -> Bool { abs(d) <= reach }
}

/// An album element as Cover Flow, iTunes style. Click a side cover to bring it to the centre; click the centre
/// to open the album, double-click it to play. Sideways swipes and ← → flip through. Only the covers near the
/// centre exist as views, so a long element costs no more than a short one.
struct CoverFlowElement: View {
    let albums: [Album]
    /// The centre cover's side (`CoverFlowGeometry.side(for:)`).
    let side: CGFloat
    /// How far apart side covers sit (`CoverFlowGeometry.spread(for:)`).
    let spread: CGFloat
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.elementPreview) private var previewing
    @Environment(\.scrollActivity) private var scrollActivity
    /// The centre album, by ID so a refreshed result keeps it in place; `lastCentre` covers it disappearing.
    @State private var centreID: PersistentID?
    @State private var lastCentre = 0
    @State private var probe = FrameProbe()
    @State private var scrollMonitor: Any?
    @State private var swipe: CGFloat = 0
    @FocusState private var focused: Bool

    /// The centre cover's scale, so the zoom's stand-in matches it exactly.
    private var centreScale: CGFloat { CoverFlowGeometry.place(distance: 0, side: side).scale }

    /// Sideways scrolling, in points, that flips one cover.
    private static let swipeStep: CGFloat = 36

    private var centre: Int {
        if let centreID, let index = albums.firstIndex(where: { $0.id == centreID }) { return index }
        return min(lastCentre, max(albums.count - 1, 0))
    }

    var body: some View {
        if albums.isEmpty { EmptyView() } else { flow }
    }

    private var flow: some View {
        let current = centre
        let paused = previewing || (scrollActivity?.isScrolling ?? false)
        return VStack(spacing: 14) {
            ZStack {
                // Where the album zoom starts and lands: a fixed, untransformed stand-in exactly over the centre
                // cover. A probe on the cover itself sat inside the 3D transform (which AppKit views can't follow)
                // and was rebuilt whenever the centre changed, so the zoom measured the wrong place or nothing.
                Color.clear
                    .frame(width: side * centreScale, height: side * centreScale)
                    .frameProbe(probe)
                    .allowsHitTesting(false)
                ForEach(max(0, current - CoverFlowGeometry.drawReach)...min(albums.count - 1, current + CoverFlowGeometry.drawReach), id: \.self) { i in
                    let place = CoverFlowGeometry.place(distance: i - current, side: side, spread: spread)
                    // One view per cover whatever its place, so moving the centre turns, slides and scales the
                    // same views into position; they never cross-fade.
                    cover(i, distance: i - current)
                        .frame(width: side, height: side)
                        .brightness(place.brightness)
                        .scaleEffect(place.scale)
                        .rotation3DEffect(.degrees(place.rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .offset(x: place.x)
                        .zIndex(place.zIndex)
                        .allowsHitTesting(!paused && CoverFlowGeometry.isVisible(distance: i - current))
                        .transition(.identity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CoverFlowGeometry.stageHeight(side: side))
            // Cut off at the page's sides only; never crop the turned covers' tops and bottoms.
            .mask { Rectangle().padding(.vertical, -side) }
            .animation(.spring(duration: 0.35, bounce: 0.1), value: current)
            caption(albums[current])
        }
        .padding(.vertical, 6)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .return]) { press in
            switch press.key {
            case .leftArrow: move(by: -1)
            case .rightArrow: move(by: 1)
            default: open(albums[current])
            }
            return .handled
        }
        .onContinuousHover { phase in
            if case .active = phase { watchScrolling(true) } else { watchScrolling(false) }
        }
        .onDisappear { watchScrolling(false) }
        // The zoom back from the album page lands on the centre cover.
        .task(id: albums[current].id) { hero.registerTile(probe, for: albums[current].id, cornerRadius: 6) }
    }

    /// A cover at `distance` from the centre. The same view structure at every distance (only values change),
    /// so a cover keeps its identity as it moves.
    private func cover(_ i: Int, distance: Int) -> some View {
        let album = albums[i]
        let isCentre = distance == 0
        // Sharp art for the centre and its neighbours, which are about to arrive there.
        return ArtworkView(albumID: album.id, size: abs(distance) <= 1 ? .large : .thumbnail, cornerRadius: 6)
            .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                                    opacity: isCentre ? 0.3 : 0, radius: 14, y: 8))
            .keyboardHighlight(isCentre && focused, cornerRadius: 6)
            .opacity(isCentre && hero.isReturning(to: album.id) ? 0 : 1)
            .contentShape(Rectangle())
            // The centre: a double-click plays, a single click (once it can't be a double) opens. A side cover
            // comes to the centre.
            .gesture(
                TapGesture(count: 2).onEnded { if isCentre { queue.play(library.snapshot.tracks(of: album)) } else { bringToCentre(i) } }
                    .exclusively(before: TapGesture().onEnded { if isCentre { open(album) } else { bringToCentre(i) } })
            )
            .onHover { if $0, isCentre, !navigationDisabled { navigator.coverTint.prefetch(.album(album.id)) } }
            .contextMenu { if isCentre { TrackContextMenu(tracks: library.snapshot.tracks(of: album)) } }
    }

    private func bringToCentre(_ i: Int) {
        centreID = albums[i].id
        lastCentre = i
    }

    /// Under the stage, never on the art.
    private func caption(_ album: Album) -> some View {
        VStack(spacing: 2) {
            Text(album.title).font(.callout.weight(.semibold)).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: side * 2.5)
        .padding(.horizontal, 24)
    }

    private func move(by step: Int) {
        bringToCentre(min(max(centre + step, 0), albums.count - 1))
    }

    private func open(_ album: Album) {
        guard !navigationDisabled else { return }
        navigator.openWhenReady(.album(album.id)) {
            hero.open(album.id, from: probe, cornerRadius: 6, navigator: navigator, reduceMotion: reduceMotion)
        }
    }

    /// While the pointer is over the stage, sideways scrolls flip covers instead of reaching the page. Vertical
    /// scrolls pass through, so the page still scrolls.
    private func watchScrolling(_ on: Bool) {
        if on, scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let handled = MainActor.assumeIsolated { flip(with: event) }
                return handled ? nil : event
            }
        } else if !on, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
            swipe = 0
        }
    }

    private func flip(with event: NSEvent) -> Bool {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        // Momentum after the fingers lift would overshoot; flips follow the fingers only.
        guard event.momentumPhase.isEmpty else { return true }
        if event.phase == .began { swipe = 0 }
        swipe -= event.scrollingDeltaX
        while swipe > Self.swipeStep { move(by: 1); swipe -= Self.swipeStep }
        while swipe < -Self.swipeStep { move(by: -1); swipe += Self.swipeStep }
        return true
    }
}
