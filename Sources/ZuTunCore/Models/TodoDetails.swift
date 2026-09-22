import Foundation

/// Optional, secondary context for a todo. Details stay out of the task's
/// title and are rendered in the owned folded callout below its task line.
public struct TodoDetails: Equatable, Sendable {
    public var state: String {
        didSet { state = Self.normalized(state) }
    }

    public var outcome: String {
        didSet { outcome = Self.normalized(outcome) }
    }

    public init(state: String = "", outcome: String = "") {
        self.state = Self.normalized(state)
        self.outcome = Self.normalized(outcome)
    }

    public var isEmpty: Bool {
        state.isEmpty && outcome.isEmpty
    }

    private static func normalized(_ value: String) -> String {
        TodoTextFormatting.normalizedTitle(value)
    }
}
