import Foundation
@testable import AIServices

public final class MockAIProvider: AIProviderProtocol, Sendable {
    public var responseQueue: [String] = []
    public var callHistory: [AICall] = []

    public enum AICall {
        case chat([ChatMessage], String, AIChatOptions)
        case image(String, String)
        case pdf(String, String)
    }

    public init() {}

    public func chat(
        messages: [ChatMessage],
        model: String,
        options: AIChatOptions
    ) async throws -> String {
        callHistory.append(.chat(messages, model, options))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func analyzeImage(
        imageData: Data,
        prompt: String,
        model: String
    ) async throws -> String {
        callHistory.append(.image(prompt, model))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func analyzePDF(
        pdfData: Data,
        prompt: String,
        model: String
    ) async throws -> String {
        callHistory.append(.pdf(prompt, model))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func isReasoningModel(_ model: String) -> Bool {
        let prefixes = ["o1-", "o3-"]
        let exactMatches = ["deepseek-reasoner"]

        return prefixes.contains { model.hasPrefix($0) } || exactMatches.contains(model)
    }
}
