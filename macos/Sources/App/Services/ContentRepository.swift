import Foundation
import Core
import Networking
import Storage

final class ContentRepository {
    private let api: APIClient
    private let database: LocalDatabase

    init(
        api: APIClient = .shared,
        database: LocalDatabase = .shared
    ) {
        self.api = api
        self.database = database
    }

    func createContent(
        sourceType: String,
        body: String,
        appName: String?,
        bundleID: String?
    ) async throws -> Content {
        try await api.createContent(
            sourceType: sourceType,
            body: body,
            appName: appName,
            bundleID: bundleID
        )
    }

    func listContents() async throws -> [Content] {
        try await api.listContents()
    }

    func fetchContentsByTag(tagId: Int) async throws -> [Content] {
        try await api.fetchContentsByTag(tagId: tagId)
    }

    func fetchContent(id: String) async throws -> Content {
        try await api.fetchContent(id: id)
    }

    func fetchCachedContent(id: String, userId: String? = nil) async throws -> Content? {
        try await database.fetchContent(id: id, userId: userId)
    }

    func fetchCachedContents(userId: String?) async throws -> [Content] {
        try await database.fetchContents(userId: userId)
    }

    func cacheContent(_ content: Content, userId: String?) async throws {
        try await database.saveContent(content, userId: userId)
    }

    func cacheContents(_ contents: [Content], userId: String?) async throws {
        try await database.saveContents(contents, userId: userId)
    }

    func claimLegacyCache(userId: String) async throws {
        try await database.claimLegacyCache(userId: userId)
    }

    func fetchParagraphs(contentId: String) async throws -> [(anchorID: String, text: String)] {
        try await database.fetchParagraphs(contentId: contentId)
    }

    func refreshParagraphs(contentId: String) async throws -> [(anchorID: String, text: String)] {
        let paragraphs = try await api.getParagraphs(contentID: contentId)
        return paragraphs.map { (anchorID: $0.anchorID, text: $0.text) }
    }

    func cacheParagraphs(
        _ paragraphs: [(anchorID: String, text: String)],
        contentId: String
    ) async throws {
        try await database.saveParagraphs(paragraphs, contentId: contentId)
    }

    func fetchExpandedDetails(contentId: String) async throws -> [Int: String] {
        try await database.fetchExpandedDetails(contentId: contentId)
    }

    func cacheExpandedDetail(
        contentId: String,
        pointIndex: Int,
        detailText: String
    ) async throws {
        try await database.saveExpandedDetail(
            contentId: contentId,
            pointIndex: pointIndex,
            detailText: detailText
        )
    }

    func expandPoint(contentID: String, pointIndex: Int) async throws -> String {
        try await api.expandPoint(contentID: contentID, pointIndex: pointIndex)
    }

    func askFollowUp(contentID: String, question: String) async throws -> String {
        try await api.askFollowUp(contentID: contentID, question: question)
    }

    func translateContent(contentID: String, targetLanguage: String) async throws -> Content {
        try await api.translateContent(
            contentID: contentID,
            targetLanguage: targetLanguage
        )
    }
}
