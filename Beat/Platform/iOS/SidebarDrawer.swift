import SwiftUI

/// The sidebar on a phone: a panel sliding in from the left over most of the width, with the page dimmed behind it,
/// instead of a full-screen list the page slides away from. Opens from the page's sidebar button or a swipe from the
/// left edge of a root page; closes on a pick, a tap on the dimmed page, or a swipe back to the left. The sidebar is
/// built afresh each time it opens, so its scroll position starts at the top (open folders are kept by `AppNavigator`).
struct SidebarDrawer<Sidebar: View>: View {
    @Binding var isOpen: Bool
    /// Root pages only: on a pushed page the same swipe goes back.
    let canSwipeOpen: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    /// How far a finger has moved the panel from where it rests (open or closed).
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.82, 340)
            let shown = min(max((isOpen ? width : 0) + drag, 0), width)
            ZStack(alignment: .leading) {
                Color.black.opacity(0.25 * shown / width)
                    .contentShape(Rectangle())
                    .allowsHitTesting(isOpen)
                    .onTapGesture { set(open: false) }
                    .gesture(dragGesture(width: width))
                let panel = UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
                // Only while it shows: the sidebar's navigation stack, left in the window while closed, answered for
                // the status bar instead of the page's, so a pale cover page kept white text over a dark system.
                if isOpen || drag > 0 {
                    sidebar()
                        // Glass: the page shows through, blurred, as with the system's own panels.
                        .scrollContentBackground(.hidden)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background { Color.clear.beatGlass(in: panel).ignoresSafeArea() }
                        .clipShape(panel)
                        .offset(x: shown - width)
                        .gesture(dragGesture(width: width))
                        // Slides away as it closes, as the offset did while it stayed.
                        .transition(.move(edge: .leading))
                }
                if !isOpen, canSwipeOpen {
                    // A thin strip along the left edge to catch the opening swipe.
                    Color.clear
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(width: width))
                }
            }
            .ignoresSafeArea(edges: .vertical)
        }
        // However it opens or closes: the page's button and sidebar picks change `isOpen` from outside.
        .animation(.snappy(duration: 0.3), value: isOpen)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                // Where the panel would come to rest, so a quick flick counts as much as a long drag.
                let resting = (isOpen ? width : 0) + value.predictedEndTranslation.width
                set(open: resting > width / 2)
            }
    }

    private func set(open: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            isOpen = open
            drag = 0
        }
    }
}
