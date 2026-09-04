import Foundation
import Testing

@testable import Cue

@Suite("JSON walking")
struct JSONValueTests {
    private func parse(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    @Test("Booleans do not arrive as numbers")
    func booleansStayBooleans() throws {
        // `JSONSerialization` hands both back as `NSNumber`, and telling them
        // apart needs the Core Foundation type. Getting it wrong turns every
        // `true` into `1`.
        let value = try parse(#"{"on": true, "count": 1}"#)
        #expect(value["on"]?.bool == true)
        #expect(value["count"]?.bool == nil)
        #expect(value["count"]?.int == 1)
    }

    @Test("A path stops at the first missing step instead of trapping")
    func pathSubscript() throws {
        let value = try parse(#"{"a": {"b": [{"c": "found"}]}}"#)
        #expect(value["a", "b", "0", "c"]?.string == "found")
        #expect(value["a", "b", "9", "c"] == nil)
        #expect(value["a", "nope", "c"] == nil)
    }

    @Test("Collecting finds every match at any depth, in order")
    func collectFindsNested() throws {
        let value = try parse("""
            {"wrapper": {"items": [
                {"row": {"n": 1}},
                {"deeper": {"another": {"row": {"n": 2}}}}
            ]}}
            """)

        let rows = value.collect("row")
        #expect(rows.count == 2)
        #expect(rows.compactMap { $0["n"]?.int } == [1, 2])
    }

    @Test("Collecting is deterministic across runs")
    func collectIsOrdered() throws {
        // Dictionary iteration order is not stable between runs, and these
        // become a list a person reads. Sorted key order is what makes two
        // runs produce the same list.
        let value = try parse("""
            {"z": {"row": {"n": 3}}, "a": {"row": {"n": 1}}, "m": {"row": {"n": 2}}}
            """)
        #expect(value.collect("row").compactMap { $0["n"]?.int } == [1, 2, 3])
    }

    @Test("Runs are joined back into the sentence they were split from")
    func runsText() throws {
        let value = try parse("""
            {"subtitle": {"runs": [
                {"text": "Song"}, {"text": " • "}, {"text": "Marconi Union"}
            ]}}
            """)
        #expect(value["subtitle"]?.runsText == "Song • Marconi Union")
    }

    @Test("A plain string reads as its own text")
    func runsTextFallsBackToString() throws {
        let value = try parse(#"{"title": "Plain"}"#)
        #expect(value["title"]?.runsText == "Plain")
    }

    @Test("An empty runs array is nothing rather than an empty string")
    func emptyRuns() throws {
        let value = try parse(#"{"subtitle": {"runs": []}}"#)
        #expect(value["subtitle"]?.runsText == nil)
    }
}
