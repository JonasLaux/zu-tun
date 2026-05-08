import Foundation

public enum TodoPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    public var id: String { rawValue }

    public var sortRank: Int {
        switch self {
        case .p1:
            1
        case .p2:
            2
        case .p3:
            3
        }
    }
}
