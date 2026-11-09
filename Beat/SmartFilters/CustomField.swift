import Foundation

/// A user-defined sort field: a value pulled out of a text tag, like the catalog number in
/// "Certainties EP (AUX002)". Sort keys carry the whole definition, so a filter stays self-contained.
struct CustomField: Codable, Identifiable, Hashable, Sendable {
    enum Extraction: Codable, Hashable, Sendable {
        case lastParentheses
        case lastBrackets
        /// A regular expression. Uses capture group 1 if the pattern has one, else the whole match.
        case pattern(String)
    }

    var id = UUID()
    var name: String
    var source: Field
    var extraction: Extraction

    /// The text fields a value can be extracted from.
    static let sources: [Field] = [.album, .title, .artist, .albumArtist, .comments, .grouping, .composer, .genre]

    static func new() -> CustomField { CustomField(name: "", source: .album, extraction: .lastParentheses) }

    var isValid: Bool {
        guard case .pattern(let pattern) = extraction else { return true }
        return !pattern.isEmpty && (try? NSRegularExpression(pattern: pattern)) != nil
    }

    var summary: String {
        let how = switch extraction {
        case .lastParentheses: "text in last ( )"
        case .lastBrackets: "text in last [ ]"
        case .pattern(let p): "pattern \(p)"
        }
        return "\(source.title) · \(how)"
    }

    func value(for track: Track) -> String? { extractor()(track) }

    /// Builds the extraction once, compiling any pattern, so sorting thousands of tracks doesn't recompile it.
    /// Returns nil for no match, an empty match or an invalid pattern.
    func extractor() -> (Track) -> String? {
        let source = source
        switch extraction {
        case .lastParentheses:
            return { Self.lastEnclosed(SmartFilterEngine.text(source, $0), open: "(", close: ")") }
        case .lastBrackets:
            return { Self.lastEnclosed(SmartFilterEngine.text(source, $0), open: "[", close: "]") }
        case .pattern(let pattern):
            guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return { _ in nil }
            }
            return { track in
                let text = SmartFilterEngine.text(source, track) as NSString
                guard let match = regex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range
                let value = text.substring(with: range).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
    }

    static func lastEnclosed(_ text: String, open: Character, close: Character) -> String? {
        guard let end = text.lastIndex(of: close), let start = text[..<end].lastIndex(of: open) else { return nil }
        let value = text[text.index(after: start)..<end].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

// MARK: Keeping embedded copies current

extension SortKey {
    /// This key with its custom field replaced by the current definition of the same ID, if there is one.
    func refreshed(_ fields: [CustomField]) -> SortKey {
        guard case .custom(let field) = self.field, let current = fields.first(where: { $0.id == field.id }) else { return self }
        var key = self
        key.field = .custom(current)
        return key
    }
}

extension SmartFilter {
    mutating func refreshCustomFields(_ fields: [CustomField]) {
        steps = steps.map { step in
            switch step {
            case .sort(let keys): .sort(keys.map { $0.refreshed(fields) })
            default: step
            }
        }
    }
}

extension PageElement {
    mutating func refreshCustomFields(_ fields: [CustomField]) {
        filter.refreshCustomFields(fields)
        appearance.sortOverride = appearance.sortOverride?.refreshed(fields)
    }
}

extension EditableFilter {
    mutating func refreshCustomFields(_ fields: [CustomField]) {
        for i in steps.indices {
            guard case .sort(var keys) = steps[i].kind else { continue }
            for j in keys.indices { keys[j].key = keys[j].key.refreshed(fields) }
            steps[i].kind = .sort(keys)
        }
    }
}
