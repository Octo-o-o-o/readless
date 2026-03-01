import Foundation

// Chat message
public struct ChatMessage: Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    // Convenience constructors
    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }
}

// Chat options
public struct AIChatOptions: Sendable {
    public let temperature: Double?
    public let maxTokens: Int
    public let topP: Double?

    public init(temperature: Double? = 0.7, maxTokens: Int = 1000, topP: Double? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    public static let `default` = AIChatOptions()
}

// AI Content types
public enum AIContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case pdf(Data)
    case url(URL)
}

// AI Errors
public enum AIError: Error, LocalizedError {
    case invalidResponse
    case rateLimitExceeded
    case authenticationFailed
    case modelNotAvailable
    case timeout
    case networkError(Error)
    case noMockResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "AI 返回了无效的响应"
        case .rateLimitExceeded: return "请求频率超限，请稍后再试"
        case .authenticationFailed: return "API 认证失败"
        case .modelNotAvailable: return "所选模型暂时不可用"
        case .timeout: return "请求超时"
        case .networkError(let error): return "网络错误: \(error.localizedDescription)"
        case .noMockResponse: return "Mock provider has no response"
        }
    }
}
