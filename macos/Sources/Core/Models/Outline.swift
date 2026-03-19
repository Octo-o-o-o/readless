import Foundation
import CryptoKit

// MARK: - Outline Point

public struct OutlinePoint: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var point: String
    public var anchors: [String]
    public var expanded: Bool
    public var detail: String?

    // Backend JSON only includes "point" and "anchors"; the other fields
    // are client-only state that defaults gracefully when absent.
    private enum CodingKeys: String, CodingKey {
        case id, point, anchors, expanded, detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.point = try container.decode(String.self, forKey: .point)
        self.anchors = try container.decodeIfPresent([String].self, forKey: .anchors) ?? []
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? Self.fallbackID(point: point, anchors: anchors)
        self.expanded = try container.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(point, forKey: .point)
        try container.encode(anchors, forKey: .anchors)
        try container.encode(expanded, forKey: .expanded)
        try container.encodeIfPresent(detail, forKey: .detail)
    }

    public init(
        point: String,
        anchors: [String] = [],
        expanded: Bool = false,
        detail: String? = nil
    ) {
        self.id = Self.fallbackID(point: point, anchors: anchors)
        self.point = point
        self.anchors = anchors
        self.expanded = expanded
        self.detail = detail
    }

    public init(
        id: String,
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

    private static func fallbackID(point: String, anchors: [String]) -> String {
        let normalizedAnchors = anchors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .sorted()
            .joined(separator: "|")
        let stableInput = "\(point.trimmingCharacters(in: .whitespacesAndNewlines))\n\(normalizedAnchors)"
        let digest = SHA256.hash(data: Data(stableInput.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "outline_\(hex)"
    }
}
