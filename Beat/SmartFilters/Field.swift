import Foundation

enum FieldType: Sendable {
    case text, number, date, bool

    var operators: [RuleOperator] {
        switch self {
        case .text: [.is, .isNot, .contains, .doesNotContain, .beginsWith, .endsWith]
        case .number: [.is, .isNot, .greaterThan, .lessThan, .inRange]
        case .date: [.inLast, .notInLast, .before, .after]
        case .bool: [.isTrue, .isFalse]
        }
    }
}

enum Field: String, Codable, CaseIterable, Sendable {
    case title, artist, albumArtist, album, composer, genre, kind, comments, grouping
    case year, rating, playCount, skipCount, bpm, bitrate, sampleRate, duration, trackNumber, discNumber
    case dateAdded, dateModified, lastPlayed, lastSkipped
    case compilation, hasArtwork

    var type: FieldType {
        switch self {
        case .title, .artist, .albumArtist, .album, .composer, .genre, .kind, .comments, .grouping: .text
        case .year, .rating, .playCount, .skipCount, .bpm, .bitrate, .sampleRate, .duration, .trackNumber, .discNumber: .number
        case .dateAdded, .dateModified, .lastPlayed, .lastSkipped: .date
        case .compilation, .hasArtwork: .bool
        }
    }

    var title: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .albumArtist: "Album Artist"
        case .album: "Album"
        case .composer: "Composer"
        case .genre: "Genre"
        case .kind: "File Kind"
        case .comments: "Comments"
        case .grouping: "Grouping"
        case .year: "Year"
        case .rating: "Rating (Stars)"
        case .playCount: "Plays"
        case .skipCount: "Skips"
        case .bpm: "BPM"
        case .bitrate: "Bit Rate (kbps)"
        case .sampleRate: "Sample Rate (Hz)"
        case .duration: "Time (Seconds)"
        case .trackNumber: "Track Number"
        case .discNumber: "Disc Number"
        case .dateAdded: "Date Added"
        case .dateModified: "Date Modified"
        case .lastPlayed: "Last Played"
        case .lastSkipped: "Last Skipped"
        case .compilation: "Compilation"
        case .hasArtwork: "Has Artwork"
        }
    }

    /// Fields that can be sorted on.
    static var sortable: [Field] { allCases.filter { $0.type != .bool } }

    /// How a group's value is derived when sorting albums, artists or genres.
    var aggregate: Aggregate {
        switch self {
        case .playCount, .skipCount, .duration: .sum
        case .rating, .bpm, .bitrate, .sampleRate: .average
        case .trackNumber, .discNumber: .min
        default: .max
        }
    }

    enum Aggregate: Sendable { case sum, average, min, max }
}

enum RuleOperator: String, Codable, CaseIterable, Sendable {
    case `is`, isNot, contains, doesNotContain, beginsWith, endsWith
    case greaterThan, lessThan, inRange
    case inLast, notInLast, before, after
    case isTrue, isFalse

    var title: String {
        switch self {
        case .is: "is"
        case .isNot: "is not"
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .beginsWith: "begins with"
        case .endsWith: "ends with"
        case .greaterThan: "is greater than"
        case .lessThan: "is less than"
        case .inRange: "is in the range"
        case .inLast: "is in the last"
        case .notInLast: "is not in the last"
        case .before: "is before"
        case .after: "is after"
        case .isTrue: "is true"
        case .isFalse: "is false"
        }
    }
}

enum DateUnit: String, Codable, CaseIterable, Sendable {
    case days, weeks, months, years

    var component: Calendar.Component {
        switch self {
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        case .years: .year
        }
    }
}

enum RuleValue: Codable, Hashable, Sendable {
    case none
    case text(String)
    case number(Double)
    case range(Double, Double)
    case date(Date)
    case relative(Int, DateUnit)
}
