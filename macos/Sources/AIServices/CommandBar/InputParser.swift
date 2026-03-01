import Foundation

public final class InputParser: Sendable {
    private let aiProvider: any AIProviderProtocol
    private let config: AIServiceConfig.StepConfig

    public init(aiProvider: any AIProviderProtocol, config: AIServiceConfig.StepConfig) {
        self.aiProvider = aiProvider
        self.config = config
    }

    public func parse(_ input: CommandBarInput) async throws -> ParsedInput {
        switch input {
        case .text(let text):
            return try await parseText(text)
        case .url(let url):
            return .url(url)
        case .image(let data):
            return .image(data)
        case .pdf(let data):
            return .pdf(data)
        case .pastedContent(let data):
            return try await detectPastedType(data)
        }
    }

    private func parseText(_ text: String) async throws -> ParsedInput {
        // 1. Check if URL
        if let url = URL(string: text), url.scheme != nil {
            return .url(url)
        }

        // 2. Check if command keyword
        if text.hasPrefix("/") || text.hasPrefix(">") {
            return .command(text)
        }

        // 3. Plain text
        return .plainText(text)
    }

    private func detectPastedType(_ data: Data) async throws -> ParsedInput {
        // Check binary signatures first (before UTF-8 decoding)
        // This prevents binary files from being misidentified as text

        // Check for image signature
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { // JPEG
            return .image(data)
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { // PNG
            return .image(data)
        }

        // Check for PDF signature
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
            return .pdf(data)
        }

        // Try to decode as UTF-8 text
        if let text = String(data: data, encoding: .utf8) {
            return try await parseText(text)
        }

        // Default to text (fallback decoding)
        return .plainText(String(decoding: data, as: UTF8.self))
    }
}

// Protocol for AI provider (to support mock)
public protocol AIProviderProtocol: Sendable {
    func chat(messages: [ChatMessage], model: String, options: AIChatOptions) async throws -> String
    func analyzeImage(imageData: Data, prompt: String, model: String) async throws -> String
    func analyzePDF(pdfData: Data, prompt: String, model: String) async throws -> String
    func isReasoningModel(_ model: String) -> Bool
}

// Make UnifiedAIProvider conform
extension UnifiedAIProvider: AIProviderProtocol {}
