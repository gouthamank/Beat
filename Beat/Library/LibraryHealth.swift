import Foundation

/// Library ▸ Health: what's worth fixing in Music. Beat never writes to the library, so the report only points the
/// way: each item names the problem and opens the album (or the song on it) to be fixed in Music.
struct LibraryHealthReport: Equatable, Sendable {
    enum Check: String, CaseIterable, Identifiable, Sendable {
        case noArtwork, noYear, duplicates, splitAlbums, missingFiles, mixedTags, missingTags

        var id: Self { self }

        var title: String {
            switch self {
            case .noArtwork: "Albums Without Artwork"
            case .noYear: "No Year"
            case .duplicates: "Possible Duplicates"
            case .splitAlbums: "Albums Split in Two"
            case .missingFiles: "Missing Files"
            case .mixedTags: "Mixed Tags Within an Album"
            case .missingTags: "No Genre or Album Artist"
            }
        }

        var explanation: String {
            switch self {
            case .noArtwork: "No song on these albums has a cover."
            case .noYear: "Songs without a year land under Timeline's “No year” and sort last by year."
            case .duplicates: "The same title and artist, within two seconds of the same length."
            case .splitAlbums: "The same title and album artist, but Music keeps them as separate albums."
            case .missingFiles: "Music lists these songs, but their files are no longer where it says."
            case .mixedTags: "Songs on one album that disagree on album artist, genre or year, or track numbers with gaps or repeats. Compilations may mix genres and years."
            case .missingTags: "Songs with no genre, or no album artist."
            }
        }

        var symbol: String {
            switch self {
            case .noArtwork: "photo"
            case .noYear: "calendar"
            case .duplicates: "square.on.square"
            case .splitAlbums: "square.split.2x1"
            case .missingFiles: "questionmark.folder"
            case .mixedTags: "tag"
            case .missingTags: "tag.slash"
            }
        }
    }

    struct Item: Identifiable, Equatable, Sendable {
        enum Target: Hashable, Sendable {
            case album(PersistentID)
            /// Its album opens with the song highlighted.
            case song(PersistentID, album: PersistentID)

            var albumID: PersistentID {
                switch self {
                case .album(let id), .song(_, let id): id
                }
            }
        }

        let target: Target
        let title: String
        let subtitle: String
        /// What's wrong with this one, when the section's title doesn't already say it all.
        var problem = ""

        var id: Target { target }
    }

    struct Section: Identifiable, Equatable, Sendable {
        let check: Check
        let items: [Item]

        var id: Check { check }
    }

    var sections: [Section]

    var problemCount: Int { sections.reduce(0) { $0 + $1.items.count } }
}

/// The checks behind `LibraryHealthReport`. Pure: `fileExists` is passed in, so tests never touch the disk. Run off the
/// main actor once per library version (~20k songs).
enum LibraryHealth {
    typealias Item = LibraryHealthReport.Item

    static func check(_ snapshot: LibrarySnapshot, fileExists: (URL) -> Bool) -> LibraryHealthReport {
        LibraryHealthReport(sections: [
            .init(check: .noArtwork, items: albumsWithoutArtwork(snapshot)),
            .init(check: .noYear, items: albumsWithoutYear(snapshot)),
            .init(check: .duplicates, items: duplicates(snapshot)),
            .init(check: .splitAlbums, items: splitAlbums(snapshot)),
            .init(check: .missingFiles, items: missingFiles(snapshot, fileExists: fileExists)),
            .init(check: .mixedTags, items: mixedTags(snapshot)),
            .init(check: .missingTags, items: missingTags(snapshot)),
        ])
    }

    static func albumsWithoutArtwork(_ snapshot: LibrarySnapshot) -> [Item] {
        snapshot.albums.filter { !snapshot.hasArtwork($0) }.map(item)
    }

    /// Whole albums, saying how many of their songs lack a year.
    static func albumsWithoutYear(_ snapshot: LibrarySnapshot) -> [Item] {
        snapshot.albums.compactMap { album in
            let tracks = snapshot.tracks(of: album)
            let missing = tracks.count { $0.year <= 0 }
            guard missing > 0 else { return nil }
            var item = item(album)
            item.problem = missing == tracks.count ? "" : "\(missing) of \(tracks.count) songs"
            return item
        }
    }

    /// Every copy of each song that appears more than once, copies together, in artist then title order.
    static func duplicates(_ snapshot: LibrarySnapshot) -> [Item] {
        let byName = Dictionary(grouping: snapshot.tracks.filter { !$0.title.isEmpty }) {
            SearchText.fold($0.title) + "\u{1}" + SearchText.fold($0.displayArtist)
        }
        var clusters: [[Track]] = []
        for tracks in byName.values where tracks.count > 1 {
            // Copies within two seconds of each other: a radio edit and the album version aren't duplicates.
            var cluster: [Track] = []
            for track in tracks.sorted(by: { ($0.duration, $0.id) < ($1.duration, $1.id) }) {
                if let last = cluster.last, track.duration - last.duration > 2 {
                    if cluster.count > 1 { clusters.append(cluster) }
                    cluster = []
                }
                cluster.append(track)
            }
            if cluster.count > 1 { clusters.append(cluster) }
        }
        clusters.sort { a, b in
            let artist = a[0].displayArtist.localizedStandardCompare(b[0].displayArtist)
            if artist != .orderedSame { return artist == .orderedAscending }
            let title = a[0].title.localizedStandardCompare(b[0].title)
            if title != .orderedSame { return title == .orderedAscending }
            return (a[0].duration, a[0].id) < (b[0].duration, b[0].id)
        }
        return clusters.flatMap { cluster in
            cluster.map { track in
                var item = item(track)
                item.problem = "\(cluster.count) copies"
                return item
            }
        }
    }

    static func splitAlbums(_ snapshot: LibrarySnapshot) -> [Item] {
        let groups = Dictionary(grouping: snapshot.albums.filter { !$0.title.isEmpty }) {
            SearchText.fold($0.title) + "\u{1}" + SearchText.fold($0.artist)
        }
        // In library order, each group where its first album falls.
        return snapshot.albums.compactMap { album -> [Item]? in
            guard let group = groups[SearchText.fold(album.title) + "\u{1}" + SearchText.fold(album.artist)],
                  group.count > 1, group.first?.id == album.id else { return nil }
            return group.map { album in
                var item = item(album)
                item.problem = "\(album.trackIDs.count.counted("song")), one of \(group.count)"
                return item
            }
        }.flatMap { $0 }
    }

    /// Only songs with a file location: synced songs on iPad and iPhone aren't files.
    static func missingFiles(_ snapshot: LibrarySnapshot, fileExists: (URL) -> Bool) -> [Item] {
        snapshot.tracks.filter { $0.location.isFileURL && !fileExists($0.location) }.map { item($0) }
    }

    static func mixedTags(_ snapshot: LibrarySnapshot) -> [Item] {
        snapshot.albums.compactMap { album in
            let tracks = snapshot.tracks(of: album)
            let problems = mixedTagProblems(tracks, compilation: album.isCompilation)
            guard !problems.isEmpty else { return nil }
            var item = item(album)
            item.problem = problems.joined(separator: ", ")
            return item
        }
    }

    /// "Mixed genres", "Track 3 missing", "Track 2 repeated"…; nothing for an album that agrees with itself.
    static func mixedTagProblems(_ tracks: [Track], compilation: Bool) -> [String] {
        guard tracks.count > 1 else { return [] }
        func distinct(_ values: [String]) -> Int { Set(values.filter { !$0.isEmpty }.map { $0.lowercased() }).count }
        var problems: [String] = []
        if distinct(tracks.map(\.albumArtist)) > 1 { problems.append("Mixed album artists") }
        if !compilation {
            if distinct(tracks.map(\.genre)) > 1 { problems.append("Mixed genres") }
            if Set(tracks.map(\.year).filter { $0 > 0 }).count > 1 { problems.append("Mixed years") }
        }
        let discs = Dictionary(grouping: tracks, by: \.discNumber)
        for disc in discs.keys.sorted() {
            let numbers = discs[disc]!.map(\.trackNumber).filter { $0 > 0 }
            guard let highest = numbers.max() else { continue }
            let prefix = discs.count > 1 ? "Disc \(disc): " : ""
            let counts = Dictionary(grouping: numbers, by: { $0 }).mapValues(\.count)
            let repeated = counts.filter { $0.value > 1 }.keys.sorted()
            let missing = (1...highest).filter { counts[$0] == nil }
            if !repeated.isEmpty { problems.append(prefix + numbered("repeated", repeated)) }
            if !missing.isEmpty { problems.append(prefix + numbered("missing", missing)) }
        }
        return problems
    }

    static func missingTags(_ snapshot: LibrarySnapshot) -> [Item] {
        snapshot.tracks.compactMap { track in
            let problem = switch (track.genre.isEmpty, track.albumArtist.isEmpty) {
            case (true, true): "No genre or album artist"
            case (true, false): "No genre"
            case (false, true): "No album artist"
            case (false, false): ""
            }
            guard !problem.isEmpty else { return nil }
            var item = item(track)
            item.problem = problem
            return item
        }
    }

    /// "Track 3 missing", "Tracks 3, 5 and 9 missing", "Tracks 3, 5, 9 and 4 more missing".
    static func numbered(_ what: String, _ numbers: [Int]) -> String {
        guard numbers.count > 1 else { return "Track \(numbers[0]) \(what)" }
        let shown = numbers.prefix(3).map(String.init)
        let list = numbers.count <= 3
            ? shown.dropLast().joined(separator: ", ") + " and " + shown.last!
            : shown.joined(separator: ", ") + " and \(numbers.count - 3) more"
        return "Tracks \(list) \(what)"
    }

    private static func item(_ album: Album) -> Item {
        Item(target: .album(album.id), title: album.title.isEmpty ? "Unknown Album" : album.title, subtitle: album.artist)
    }

    private static func item(_ track: Track) -> Item {
        Item(target: .song(track.id, album: track.albumID), title: track.title,
             subtitle: [track.displayArtist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}
