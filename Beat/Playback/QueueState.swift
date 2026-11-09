import Foundation

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Pure queue logic (ordering, shuffle, repeat, skipping). No AVFoundation, so it's unit-tested directly.
struct QueueState: Equatable, Sendable {
    private(set) var items: [Track] = []
    /// The unshuffled order, kept while shuffle is on so turning it off restores it.
    private(set) var original: [Track]?
    private(set) var index: Int?
    /// How many songs straight after the current one were added with Play Next or Add to Queue.
    /// They play before the rest of the list, like Music's Up Next, and shuffle leaves them in order.
    private(set) var queuedCount = 0
    var repeatMode: RepeatMode = .off

    var isShuffled: Bool { original != nil }
    var current: Track? { index.map { items[$0] } }
    var upNext: ArraySlice<Track> { index.map { items[($0 + 1)...] } ?? [] }
    /// The songs you added, in the order they'll play.
    var queued: ArraySlice<Track> { upNext.prefix(queuedCount) }
    /// The rest of the list playback started from.
    var continuing: ArraySlice<Track> { upNext.dropFirst(queuedCount) }

    mutating func load<G: RandomNumberGenerator>(_ tracks: [Track], startAt start: Int, shuffled: Bool, using rng: inout G) {
        items = tracks
        original = nil
        queuedCount = 0
        index = tracks.isEmpty ? nil : min(max(start, 0), tracks.count - 1)
        if shuffled { setShuffle(true, using: &rng) }
    }

    mutating func load(_ tracks: [Track], startAt start: Int = 0, shuffled: Bool = false) {
        var rng = SystemRandomNumberGenerator()
        load(tracks, startAt: start, shuffled: shuffled, using: &rng)
    }

    /// The index to play after `i`. `manual` is a user-initiated skip, which ignores repeat-one.
    func index(after i: Int, manual: Bool, isPlayable: (Track) -> Bool = { _ in true }) -> Int? {
        guard !items.isEmpty else { return nil }
        if repeatMode == .one, !manual, isPlayable(items[i]) { return i }
        var j = i
        for _ in 0..<items.count {
            j += 1
            if j == items.count {
                guard repeatMode != .off else { return nil }
                j = 0
            }
            if isPlayable(items[j]) { return j }
        }
        return nil
    }

    func index(before i: Int, isPlayable: (Track) -> Bool = { _ in true }) -> Int? {
        var j = i
        while j > 0 {
            j -= 1
            if isPlayable(items[j]) { return j }
        }
        if repeatMode == .all, let last = items.indices.last(where: { $0 > i && isPlayable(items[$0]) }) {
            return last
        }
        return nil
    }

    mutating func move(to i: Int) {
        guard items.indices.contains(i) else { return }
        if let current = index, i != current {
            // Moving into the added songs uses up the ones passed; going back or past them ends the run.
            queuedCount = i > current && i <= current + queuedCount ? queuedCount - (i - current) : 0
        }
        index = i
    }

    mutating func setShuffle<G: RandomNumberGenerator>(_ on: Bool, using rng: inout G) {
        guard on != isShuffled else { return }
        if on {
            original = items
            guard let i = index else { items.shuffle(using: &rng); return }
            // The current track stays and plays first, then the songs you added, then everything else shuffled.
            let queued = Array(items[(i + 1)..<(i + 1 + queuedCount)])
            var rest = Array(items[..<i]) + Array(items[(i + 1 + queuedCount)...])
            rest.shuffle(using: &rng)
            items = [items[i]] + queued + rest
            index = 0
        } else if let original {
            let currentID = current?.id
            items = original
            self.original = nil
            index = currentID.flatMap { id in items.firstIndex { $0.id == id } } ?? (items.isEmpty ? nil : 0)
        }
    }

    mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    /// Play Next: the front of the added songs.
    mutating func insertNext(_ tracks: [Track]) {
        insertQueued(tracks, after: 0)
    }

    /// Add to Queue: the end of the added songs, still ahead of the rest of the list.
    mutating func append(_ tracks: [Track]) {
        insertQueued(tracks, after: queuedCount)
    }

    /// Inserts `tracks` `offset` songs after the current one, in both orders, and counts them as added.
    private mutating func insertQueued(_ tracks: [Track], after offset: Int) {
        guard let i = index else { load(tracks); return }
        items.insert(contentsOf: tracks, at: i + 1 + offset)
        if var o = original {
            let currentID = items[i].id
            let at = (o.firstIndex { $0.id == currentID } ?? o.count - 1) + 1 + offset
            o.insert(contentsOf: tracks, at: min(at, o.count))
            original = o
        }
        queuedCount += tracks.count
    }

    /// Removes an upcoming or past item. The current item can't be removed.
    mutating func remove(at i: Int) {
        guard items.indices.contains(i), i != index else { return }
        let removed = items.remove(at: i)
        if let current = index {
            if i < current { index = current - 1 }
            if i > current, i <= current + queuedCount { queuedCount -= 1 }
        }
        if var o = original, let at = o.firstIndex(where: { $0.id == removed.id }) {
            o.remove(at: at)
            original = o
        }
    }

    /// Reorders the songs after the current one; offsets are relative to `upNext`. The unshuffled
    /// order is left alone, so turning shuffle off still restores the original order. Callers keep a
    /// move on one side of the added/continuing boundary, so `queuedCount` stays right.
    mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let current = index else { return }
        let next = Array(items[(current + 1)...])
        let valid = source.filter { next.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { next[$0] }
        var rest = next.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let insertAt = (destination - valid.filter { $0 < destination }.count).clamped(to: 0...rest.count)
        rest.insert(contentsOf: moving, at: insertAt)
        items.replaceSubrange((current + 1)..., with: rest)
    }

    /// Removes every song after the current one, from the shuffled and unshuffled orders alike.
    mutating func clearUpNext() {
        guard let current = index else { return }
        let removed = items[(current + 1)...].map(\.id)
        items.removeSubrange((current + 1)...)
        queuedCount = 0
        if var o = original {
            let currentID = items[current].id
            for id in removed where id != currentID {
                if let at = o.firstIndex(where: { $0.id == id }) { o.remove(at: at) }
            }
            original = o
        }
    }

    /// Removes only the songs you added, leaving the rest of the list.
    mutating func clearQueued() {
        guard let current = index, queuedCount > 0 else { return }
        for _ in 0..<queuedCount { remove(at: current + 1) }
    }

    mutating func clear() {
        items = []
        original = nil
        index = nil
        queuedCount = 0
    }
}
