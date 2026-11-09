import SwiftUI

/// Opens the queue in a popover, so seeing what's next doesn't add clutter to the bar or Now Playing.
struct QueueButton: View {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(ArtworkCache.self) private var artwork
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "list.bullet")
                .foregroundStyle(showing ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("Queue")
        .popover(isPresented: $showing, arrowEdge: .top) {
            QueuePopover()
                // Popovers are separately hosted and don't inherit the window's environment objects.
                .environment(queue)
                .environment(artwork)
        }
    }
}

/// What plays after the current song: the songs you added (Play Next, Add to Queue), then the rest of
/// the list playback started from. Drag to reorder within each part; right-click to play or remove.
private struct QueuePopover: View {
    /// A long list (all of Songs) would make an endless popover; the rest is summarised.
    private static let continuingLimit = 100

    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        let state = queue.state
        let queued = Array(state.queued)
        let continuing = Array(state.continuing.prefix(Self.continuingLimit))
        let more = state.continuing.count - continuing.count

        List {
            if let current = state.current {
                Section("Now Playing") {
                    QueueRow(track: current, isCurrent: true)
                }
            }
            Section {
                if queued.isEmpty {
                    Text("Songs you add with Play Next or Add to Queue appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(queued.enumerated()), id: \.offset) { offset, track in
                    row(track, upNextOffset: offset)
                }
                .onMove { queue.moveUpNext(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Queue")
                    Spacer()
                    if !queued.isEmpty {
                        Button("Clear") { queue.clearQueued() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            if !continuing.isEmpty {
                Section {
                    ForEach(Array(continuing.enumerated()), id: \.offset) { offset, track in
                        row(track, upNextOffset: queued.count + offset)
                    }
                    .onMove { source, destination in
                        queue.moveUpNext(fromOffsets: IndexSet(source.map { $0 + queued.count }),
                                         toOffset: destination + queued.count)
                    }
                    if more > 0 {
                        Text("and \(more.formatted()) more")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Up Next")
                }
            }
        }
        .frame(width: 340, height: 440)
    }

    /// `upNextOffset` counts from the song after the current one.
    private func row(_ track: Track, upNextOffset: Int) -> some View {
        QueueRow(track: track, isCurrent: false)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { play(upNextOffset) }
            .contextMenu {
                Button("Play Now", systemImage: "play") { play(upNextOffset) }
                Button("Remove from Queue", systemImage: "minus.circle") { remove(upNextOffset) }
            }
    }

    private func play(_ upNextOffset: Int) {
        guard let current = queue.state.index else { return }
        queue.jump(to: current + 1 + upNextOffset)
    }

    private func remove(_ upNextOffset: Int) {
        guard let current = queue.state.index else { return }
        queue.remove(at: current + 1 + upNextOffset)
    }
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(albumID: track.albumID, cornerRadius: 4)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(track.duration.trackTime)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
