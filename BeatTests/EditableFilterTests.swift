import XCTest
@testable import Beat

final class EditableFilterTests: XCTestCase {
    func testPresetsRoundTripThroughEditorModel() {
        for preset in Presets.all {
            XCTAssertEqual(EditableFilter(preset).makeFilter(), preset, preset.name)
        }
    }

    func testDuplicatedRuleNodeHasSameContentAndFreshIDs() {
        let inner = EditGroup(match: .any, nodes: [EditNode(content: .rule(.make(field: .genre))),
                                                   EditNode(content: .rule(.make(field: .year)))])
        let original = EditNode(content: .group(inner))
        let copy = original.duplicated()
        XCTAssertEqual(copy.node, original.node, "same rules")

        func ids(_ node: EditNode) -> [UUID] {
            guard case .group(let g) = node.content else { return [node.id] }
            return [node.id, g.id] + g.nodes.flatMap(ids)
        }
        XCTAssertTrue(Set(ids(copy)).isDisjoint(with: ids(original)), "every level gets a new id")
    }

    func testDuplicateGetsNewIdentity() {
        let original = EditableFilter(Presets.all[0])
        let copy = original.duplicated()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, original.name + " Copy")
        XCTAssertEqual(copy.makeFilter().steps, original.makeFilter().steps)
    }

    func testDefaultValuesFitTheirOperators() {
        for field in Field.allCases {
            for op in field.type.operators {
                XCTAssertTrue(RuleValue.defaultValue(for: field, op: op).fits(op, field: field), "\(field) \(op)")
            }
        }
    }

    func testNewFilterMatchesWholeLibraryBeforeLimit() {
        let tracks = (1...60).map { Track.fixture(id: PersistentID($0)) }
        let lib = PreparedLibrary(snapshot: .build(tracks: tracks))
        let result = SmartFilterEngine.evaluate(EditableFilter.new().makeFilter(), in: lib)
        XCTAssertEqual(result.tracks.count, 50, "empty 'artist contains' matches all; limit keeps 50")
    }
}
