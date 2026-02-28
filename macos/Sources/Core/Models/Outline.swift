import Foundation

// MARK: - Outline Point

public struct OutlinePoint: Identifiable, Codable, Sendable {
    public let id: String
    public var point: String
    public var anchors: [String]
    public var expanded: Bool
    public var detail: String?

    public init(
        id: String = UUID().uuidString,
        point: String,
        anchors: [String] = [],
        expanded: Bool = false,
        detail: String? = nil
    ) {
        self.id = id
        self.point = point
        self.anchors = anchors
        self.expanded = expanded
        self.detail = detail
    }
}
