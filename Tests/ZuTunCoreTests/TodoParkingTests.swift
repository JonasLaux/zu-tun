import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo parking")
struct TodoParkingTests {
    private let now = Date(timeIntervalSince1970: 1_735_689_600)

    @Test("round trips timed and indefinite parking with canonical UTC timestamps")
    func roundTripsParkingMetadata() throws {
        let returnDate = now.addingTimeInterval(3_661.123)
        let document = TodoDocument(lines: [
            .todo(TodoItem(isCompleted: false, priority: .p1, title: "Timed", parking: .until(returnDate))),
            .todo(TodoItem(isCompleted: false, priority: .p2, title: "Indefinite", parking: .indefinite))
        ])

        let rendered = document.renderedMarkdown()
        #expect(rendered.contains("<!-- zutun-parked: 2025-01-01T01:01:01.123Z -->"))
        #expect(rendered.contains("<!-- zutun-parked: indefinite -->"))

        let reparsed = TodoMarkdownParser.parse(rendered)
        #expect(reparsed.todos.map(\.parking) == [.until(returnDate), .indefinite])
    }

    @Test("parses parking independently of tag and reference metadata order")
    func parsesMetadataInAnyOrder() throws {
        let referenceID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let markdown = """
        - [ ] First <!-- zutun-parked: 2025-01-02T03:04:05Z --> <!-- zutun-tags: [\"work\"] --> <!-- zutun-id: \(referenceID.uuidString) -->
        - [ ] Second <!-- zutun-id: \(referenceID.uuidString) --> <!-- zutun-parked: indefinite --> <!-- zutun-tags: [\"home\"] -->
        """

        let todos = TodoMarkdownParser.parse(markdown).todos

        #expect(todos[0].parking == .until(Date(timeIntervalSince1970: 1_735_787_045)))
        #expect(todos[0].tagIDs == ["work"])
        #expect(todos[0].referenceID == referenceID)
        #expect(todos[0].title == "First")
        #expect(todos[1].parking == .indefinite)
        #expect(todos[1].tagIDs == ["home"])
        #expect(todos[1].referenceID == referenceID)
        #expect(todos[1].title == "Second")
    }

    @Test("accepts explicit timezone timestamps with and without fractional seconds")
    func parsesTimestampVariants() throws {
        let markdown = """
        - [ ] Whole second <!-- zutun-parked: 2025-01-02T03:04:05+01:00 -->
        - [ ] Fractional second <!-- zutun-parked: 2025-01-02T03:04:05.125Z -->
        - [ ] Missing timezone <!-- zutun-parked: 2025-01-02T03:04:05 -->
        """

        let todos = TodoMarkdownParser.parse(markdown).todos
        #expect(todos[0].parking == .until(Date(timeIntervalSince1970: 1_735_783_445)))
        #expect(todos[1].parking == .until(Date(timeIntervalSince1970: 1_735_787_045.125)))
        #expect(todos[2].parking == nil)
        #expect(todos[2].title.contains("zutun-parked: 2025-01-02T03:04:05"))
    }

    @Test("consumes duplicate valid parking metadata so clearing parking stays cleared")
    func clearsDuplicateParkingMetadata() throws {
        let markdown = "- [ ] Duplicate <!-- zutun-parked: 2025-01-02T03:04:05Z --> <!-- zutun-parked: indefinite -->"
        var document = TodoMarkdownParser.parse(markdown)
        let item = try #require(document.todos.first)

        #expect(item.parking == .indefinite)
        #expect(!item.title.contains("zutun-parked:"))
        #expect(document.updateTodo(id: item.id) { $0.parking = nil })

        let reparsed = try #require(TodoMarkdownParser.parse(document.renderedMarkdown()).todos.first)
        #expect(reparsed.parking == nil)
    }

    @Test("keeps malformed parking metadata visible through unrelated edits")
    func preservesMalformedParkingMetadata() throws {
        let markdown = "- [ ] Waiting <!-- zutun-parked: when-unblocked --> <!-- zutun-tags: [\"work\"] -->"
        var document = TodoMarkdownParser.parse(markdown)
        let item = try #require(document.todos.first)

        #expect(item.parking == nil)
        #expect(item.title.contains("zutun-parked: when-unblocked"))
        #expect(document.updateTodo(id: item.id) { $0.title += " for approval" })

        let rendered = document.renderedMarkdown()
        #expect(rendered.contains("<!-- zutun-parked: when-unblocked -->"))
        let reparsed = TodoMarkdownParser.parse(rendered)
        #expect(reparsed.todos.first?.parking == nil)
        #expect(reparsed.todos.first?.title.contains("zutun-parked: when-unblocked") == true)
        #expect(reparsed.todos.first?.tagIDs == ["work"])
    }

    @Test("expires timed parking exactly at its return date and ignores completed tasks")
    func appliesParkingAtExactBoundary() {
        let returnDate = now.addingTimeInterval(3_600)
        let timed = TodoItem(isCompleted: false, priority: nil, title: "Timed", parking: .until(returnDate))
        let completed = TodoItem(isCompleted: true, priority: nil, title: "Done", parking: .indefinite)

        #expect(timed.isParked(at: returnDate.addingTimeInterval(-0.001)))
        #expect(!timed.isParked(at: returnDate))
        #expect(!completed.isParked(at: now))
    }

    @Test("keeps open todos complete, sorts parked todos, and finds the next return")
    func documentQueries() {
        let earlier = now.addingTimeInterval(1_800)
        let later = now.addingTimeInterval(7_200)
        let document = TodoDocument(lines: [
            .todo(TodoItem(isCompleted: false, priority: .p2, title: "Later", parking: .until(later))),
            .todo(TodoItem(isCompleted: false, priority: .p1, title: "Earlier", parking: .until(earlier))),
            .todo(TodoItem(isCompleted: false, priority: .p3, title: "Forever", parking: .indefinite)),
            .todo(TodoItem(isCompleted: false, priority: .p1, title: "Active")),
            .todo(TodoItem(isCompleted: false, priority: .p2, title: "Expired", parking: .until(now))),
            .todo(TodoItem(isCompleted: true, priority: .p1, title: "Completed", parking: .until(earlier)))
        ])

        #expect(document.openTodos.count == 5)
        #expect(document.parkedTodos(at: now).map(\.title) == ["Earlier", "Later", "Forever"])
        #expect(document.activeTodos(at: now).map(\.title) == ["Active", "Expired"])
        #expect(document.nextParkingDate(after: now) == earlier)
        #expect(document.nextParkingDate(after: earlier) == later)
    }

    @Test("retains multiline titles, tags, and references when parking")
    func retainsOtherTodoMetadata() throws {
        let referenceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let item = TodoItem(
            isCompleted: false,
            priority: .p1,
            title: "Review **the plan**\n\nThen send it",
            tagIDs: ["work"],
            referenceID: referenceID,
            parking: .until(now.addingTimeInterval(86_400))
        )

        let parsed = try #require(TodoMarkdownParser.parse(item.markdownLine).todos.first)
        #expect(parsed.title == item.title)
        #expect(parsed.tagIDs == item.tagIDs)
        #expect(parsed.referenceID == referenceID)
        #expect(parsed.parking == item.parking)
        #expect(parsed.priority == .p1)
    }
}
