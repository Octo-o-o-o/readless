import Foundation
import Core

// Input from user
public enum CommandBarInput: Sendable {
    case text(String)
    case url(URL)
    case image(Data)
    case pdf(Data)
    case pastedContent(Data)
}

// Parsed input type
public enum ParsedInput: Sendable, Equatable {
    case plainText(String)
    case command(String)
    case url(URL)
    case image(Data)
    case pdf(Data)

    public static func == (lhs: ParsedInput, rhs: ParsedInput) -> Bool {
        switch (lhs, rhs) {
        case (.plainText(let a), .plainText(let b)): return a == b
        case (.command(let a), .command(let b)): return a == b
        case (.url(let a), .url(let b)): return a == b
        case (.image(let a), .image(let b)): return a == b
        case (.pdf(let a), .pdf(let b)): return a == b
        default: return false
        }
    }
}

// User intent
public struct UserIntent: Codable, Sendable {
    public enum IntentType: String, Codable, Sendable {
        case createContent = "create_content"
        case searchContent = "search_content"
        case generatePodcast = "generate_podcast"
        case openContent = "open_content"
    }

    public let intent: IntentType
    public let params: [String: String]
    public let confidence: Double

    public init(intent: IntentType, params: [String: String], confidence: Double) {
        self.intent = intent
        self.params = params
        self.confidence = confidence
    }
}

// Extracted content
public struct ExtractedContent: Sendable {
    public let text: String
    public let source: SourceType
    public let title: String?
    public let summary: String?

    public init(text: String, source: SourceType, title: String? = nil, summary: String? = nil) {
        self.text = text
        self.source = source
        self.title = title
        self.summary = summary
    }
}

// Submission mode
public enum SubmissionMode: Sendable {
    case quickImport    // Enter
    case reviewFirst    // Cmd+Enter
}

// Execution result
public enum ExecutionResult: Sendable {
    case contentCreated(Content)
    case searchCompleted([Content])
    case podcastGenerated(URL)
    case contentOpened(Content)
    case reviewPending(ContentPreview)
}

// Content preview
public struct ContentPreview: Sendable {
    public enum PreviewType: Sendable {
        case creation
        case search
        case podcast
        case open
    }

    public let type: PreviewType
    public let title: String
    public let summary: String
    public let sourceType: SourceType?
    public let metadata: [String: String]

    public init(type: PreviewType, title: String, summary: String, sourceType: SourceType? = nil, metadata: [String: String] = [:]) {
        self.type = type
        self.title = title
        self.summary = summary
        self.sourceType = sourceType
        self.metadata = metadata
    }
}
