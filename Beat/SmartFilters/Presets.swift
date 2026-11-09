import Foundation

/// Built-in smart filters, in Home order. They seed the Home page on first launch.
enum Presets {

    static let all: [SmartFilter] = [
        SmartFilter(
            id: UUID(), name: "Recently Added",
            output: .albums,
            steps: [.sort([.init(field: .field(.dateAdded), ascending: false)]), .limit(.init(count: 24, unit: .albums))]
        ),
        SmartFilter(
            id: UUID(), name: "Recently Played",
            output: .albums,
            steps: [
                .filter(RuleGroup(nodes: [.rule(Rule(field: .lastPlayed, op: .inLast, value: .relative(3, .months)))])),
                .sort([.init(field: .field(.lastPlayed), ascending: false)]),
                .limit(.init(count: 24, unit: .albums)),
            ]
        ),
        SmartFilter(
            id: UUID(), name: "Random Albums",
            output: .albums,
            steps: [.sort([.init(field: .random, ascending: true)]), .limit(.init(count: 16, unit: .albums))]
        ),
        SmartFilter(
            id: UUID(), name: "Most Played",
            output: .songs,
            steps: [
                .filter(RuleGroup(nodes: [.rule(Rule(field: .playCount, op: .greaterThan, value: .number(0)))])),
                .sort([.init(field: .field(.playCount), ascending: false)]),
                .limit(.init(count: 40, unit: .songs)),
            ]
        ),
        SmartFilter(
            id: UUID(), name: "Forgotten Favorites",
            output: .songs,
            steps: [
                .filter(RuleGroup(match: .all, nodes: [
                    .group(RuleGroup(match: .any, nodes: [
                        .rule(Rule(field: .rating, op: .greaterThan, value: .number(3))),
                        .rule(Rule(field: .playCount, op: .greaterThan, value: .number(9))),
                    ])),
                    .rule(Rule(field: .lastPlayed, op: .notInLast, value: .relative(6, .months))),
                ])),
                .sort([.init(field: .random, ascending: true)]),
                .limit(.init(count: 40, unit: .songs)),
            ]
        ),
        SmartFilter(
            id: UUID(), name: "Top Artists",
            output: .artists,
            steps: [.sort([.init(field: .field(.playCount), ascending: false)]), .limit(.init(count: 16, unit: .artists))]
        ),
        SmartFilter(
            id: UUID(), name: "Never Played",
            output: .albums,
            steps: [
                .filter(RuleGroup(nodes: [.rule(Rule(field: .playCount, op: .is, value: .number(0)))])),
                .sort([.init(field: .random, ascending: true)]),
                .limit(.init(count: 16, unit: .albums)),
            ]
        ),
        SmartFilter(
            id: UUID(), name: "Top Rated",
            output: .songs,
            steps: [
                .filter(RuleGroup(nodes: [.rule(Rule(field: .rating, op: .greaterThan, value: .number(3)))])),
                .sort([.init(field: .field(.rating), ascending: false), .init(field: .field(.playCount), ascending: false)]),
                .limit(.init(count: 40, unit: .songs)),
            ]
        ),
        SmartFilter(
            id: UUID(), name: "Your Genres",
            output: .genres,
            steps: [.sort([.init(field: .field(.playCount), ascending: false)]), .limit(.init(count: 16, unit: .genres))]
        ),
    ]

    /// A Home page of the built-ins. Fresh IDs each time, so a re-added Home never collides with an existing one.
    static func homePage() -> SidebarNode {
        .page("Home", symbol: "house", all.map { PageElement(filter: $0).withNewID() })
    }
}
