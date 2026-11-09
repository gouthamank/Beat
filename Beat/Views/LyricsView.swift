import SwiftUI

/// The lyrics side of Now Playing: synced lyrics follow the song and seek on click; plain lyrics just scroll.
struct LyricsView: View {
    let track: Track
    let palette: ArtworkPalette?
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.lyricsProvider) private var provider
    @AppStorage("lyrics.online") private var online = false
    @State private var lyrics: Lyrics?
    @State private var confirmingOnline = false
    /// Hand scrolling holds off auto-scroll until this moment.
    @State private var pausedUntil = Date.distantPast

    private struct LoadKey: Equatable {
        let track: PersistentID
        let online: Bool
    }

    private var primary: Color { palette?.primary.color ?? .primary }
    private var secondary: AnyShapeStyle { palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary) }

    var body: some View {
        Group {
            switch lyrics {
            case nil:
                ProgressView().controlSize(.small)
            case .synced(let lines):
                synced(lines)
            case .plain(let text):
                plain(text)
            case .instrumental:
                message("Instrumental")
            case .missing:
                noLyrics
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .task(id: LoadKey(track: track.id, online: online)) {
            withAnimation(.easeOut(duration: 0.15)) { lyrics = nil }
            let found = await provider?.lyrics(for: track, online: online) ?? .missing
            withAnimation(.easeInOut(duration: 0.3)) { lyrics = found }
        }
        .confirmationDialog("Search for lyrics online?", isPresented: $confirmingOnline) {
            Button("Search Online") { online = true }
        } message: {
            Text("Beat will send each playing song's artist, title, album and length to LRCLIB (lrclib.net) to find synced lyrics. You can turn this off in Beat ▸ Settings.")
        }
    }

    // MARK: Synced

    private func synced(_ lines: [LyricLine]) -> some View {
        let current = LRC.currentIndex(in: lines, at: queue.currentTime)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.title2.bold())
                            .foregroundStyle(primary)
                            .opacity(index == current ? 1 : 0.35)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { queue.seek(to: line.time) }
                            .id(index)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: current)
                // Room above and below so the first and last lines can reach the reading position.
                .padding(.vertical, 220)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { pausedUntil = .now.addingTimeInterval(4) }
            }
            .onChange(of: current) { _, index in
                guard let index, Date.now >= pausedUntil else { return }
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(index, anchor: Self.readingPosition) }
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: Self.readingPosition) }
            }
            .mask(Self.edgeFade)
        }
    }

    /// The current line sits about a third of the way down.
    private static let readingPosition = UnitPoint(x: 0.5, y: 0.33)

    private static let edgeFade = LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: Plain and empty

    private func plain(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .lineSpacing(6)
                .foregroundStyle(primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 60)
        }
        .scrollIndicators(.hidden)
        .mask(Self.edgeFade)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.title3).foregroundStyle(secondary)
    }

    private var noLyrics: some View {
        VStack(spacing: 12) {
            message("No lyrics for this song")
            if !online {
                Button("Search Online…") { confirmingOnline = true }
                    .beatGlassButtonStyle()
            }
        }
    }
}
