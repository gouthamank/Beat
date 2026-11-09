import Foundation

/// What a new element starts with: the defaults saved in Settings ▸ New Elements, else the built-in ones
/// (`EditableFilter.new()` with default appearance). Saved as a `PageElement`, whose decoding already
/// tolerates missing appearance fields, so older saved defaults keep loading.
enum NewElementDefaults {
    static let key = "elements.newDefault"

    static var builtIn: PageElement {
        let filter = EditableFilter.new()
        return PageElement(filter: filter.makeFilter(), appearance: .defaults(for: filter.output))
    }

    /// The saved defaults, or nil when there are none or they no longer decode.
    static func saved(in defaults: UserDefaults = .standard) -> PageElement? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PageElement.self, from: data)
    }

    /// The defaults to start a new element from, with a fresh id and custom fields brought up to date.
    static func current(in defaults: UserDefaults = .standard, customFields: [CustomField]) -> PageElement {
        var element = (saved(in: defaults) ?? builtIn).withNewID()
        element.refreshCustomFields(customFields)
        return element
    }

    static func save(_ element: PageElement, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(element) else { return }
        defaults.set(data, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// "Songs · 1 rule · Shelf, 4 rows", for Settings.
    static func summary(_ element: PageElement) -> String {
        let rules = element.filter.steps.reduce(0) { count, step in
            if case .filter(let group) = step { count + group.ruleCount } else { count }
        }
        let look = element.appearance
        let rows = look.rows == ElementAppearance.allRows ? "all rows" : "\(look.rows) \(look.rows == 1 ? "row" : "rows")"
        return "\(element.filter.output.title) · \(rules) \(rules == 1 ? "rule" : "rules") · \(look.layout.rawValue.capitalized), \(rows)"
    }
}

extension PageElement {
    func refreshingCustomFields(_ fields: [CustomField]) -> PageElement {
        var copy = self
        copy.refreshCustomFields(fields)
        return copy
    }
}

private extension RuleGroup {
    var ruleCount: Int {
        nodes.reduce(0) { count, node in
            switch node {
            case .rule: count + 1
            case .group(let inner): count + inner.ruleCount
            }
        }
    }
}
