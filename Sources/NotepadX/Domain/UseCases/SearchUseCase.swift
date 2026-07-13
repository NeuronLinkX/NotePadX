import Foundation

struct SearchUseCase: Sendable {
    private let searchIndex: SearchIndexService

    init(searchIndex: SearchIndexService) {
        self.searchIndex = searchIndex
    }

    func search(query: String, filters: SearchFilters = SearchFilters()) async throws -> [SearchHit] {
        try await searchIndex.search(query: query, filters: filters)
    }
}
