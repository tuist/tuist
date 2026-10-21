import Foundation
import Testing

@MainActor
struct AtlasBusinessTests {
    private let item = """
    {"id":"example","fields":{"title":"Follow up","status":"open","assignee_name":"Taylor"},
    "can_edit":true,"can_delete":true}
    """
    private var overview: Data {
        Data("""
        {"items":[\(item)],"page":2,"total_pages":3,"total_count":51,"can_write":true,
        "options":{"users":[],"accounts":[],"segments":[],"statuses":[],"deal_stages":[]},
        "summary":[{"month":"2026-10","currency":"EUR","amount":"123456789.13"}]}
        """.utf8)
    }

    @Test func loadsPermissionsPaginationAndUnroundedCurrencyValues() async throws {
        let model = AtlasBusiness(resource: .tasks) { _ in overview }
        await model.load(query: "Follow", page: 2)
        #expect(model.page?.totalCount == 51 && model.page?.page == 2)
        #expect(model.page?.summary.first?.amount == "123456789.13")
        #expect(model.page?.canWrite == true)
        #expect(model.page?.items.first?["assignee_name"] == "Taylor")
        #expect(model.query == "Follow")
    }

    @Test func failedMutationRetainsContentButSuccessfulSaveSurvivesARefreshFailure() async {
        var failure = false
        var mutationFails = true
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["action"] as? String == "create", !mutationFails { return Data("{\"item\":\(item)}".utf8) }
            if failure { throw AtlasAuthenticationError(kind: "server", message: "Try again") }
            return overview
        }
        await model.load()
        failure = true
        #expect(!(await model.save(fields: ["title": "Follow up"], editing: nil)))
        #expect(model.page?.items.first?["title"] == "Follow up")
        mutationFails = false
        #expect(await model.save(fields: ["title": "Follow up"], editing: nil))
        #expect(model.records["example"]?["title"] == "Follow up")
        #expect(model.errorMessage?.hasPrefix("Saved.") == true && !model.busy)
    }

    @Test func confirmedDeletionDoesNotReappearWhenReloadFailsAndRevokedReadClearsData() async throws {
        var failure: String?
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["action"] as? String == "delete" { return Data("{\"deleted\":true}".utf8) }
            if let failure { throw AtlasAuthenticationError(kind: failure, message: "Unavailable") }
            return overview
        }
        await model.load()
        let record = try #require(model.page?.items.first)
        failure = "server"
        #expect(await model.delete(record))
        #expect(model.page?.items.isEmpty == true && model.records[record.id] == nil)
        failure = "forbidden"
        await model.loadMore()
        #expect(model.forbidden && model.page == nil && model.records.isEmpty && !model.nextPageFailed)
        failure = nil
        await model.load()
        #expect(!model.forbidden && model.page?.items.count == 1)
    }

    @Test func inFlightMutationPreventsDoubleSubmission() async {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["action"] as? String == "create" {
                return await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
            }
            return overview
        }
        let save = Task { await model.save(fields: ["title": "Follow up"], editing: nil) }
        for await _ in started.stream { break }
        #expect(!(await model.save(fields: ["title": "Duplicate"], editing: nil)))
        finish?.resume(returning: Data("{\"item\":\(item)}".utf8))
        #expect(await save.value)
        #expect(!model.busy)
    }

    @Test func scrollingAppendsDistinctRecordsAndRetainsRowsUntilExplicitRetry() async throws {
        var fail = true
        let model = AtlasBusiness(resource: .tasks) { action in
            let page = action["page"] as? Int ?? 1
            if page == 2, fail { throw AtlasAuthenticationError(kind: "server", message: "Try again") }
            return try response(ids: page == 1 ? ["one", "two"] : ["two", "three"], page: page)
        }
        await model.load()
        await model.loadMore()
        #expect(model.page?.items.map(\.id) == ["one", "two"] && model.nextPageFailed)
        fail = false
        await model.loadMore()
        #expect(model.page?.items.map(\.id) == ["one", "two"])
        await model.loadMore(retry: true)
        #expect(model.page?.items.map(\.id) == ["one", "two", "three"])
        #expect(model.page?.page == 2 && !model.nextPageFailed && !model.busy)
        await model.load()
        #expect(model.page?.items.map(\.id) == ["one", "two"] && model.page?.page == 1)
    }

    @Test func newFiltersReplacePendingScrollResultsAndKeepSearch() async throws {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["page"] as? Int == 2 {
                return await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
            }
            let filters = action["filters"] as? [String: String] ?? [:]
            return try response(ids: filters["status"] == "completed" ? ["done"] : ["open"], page: 1)
        }
        await model.load(query: "Follow")
        let scrolling = Task { await model.loadMore() }
        for await _ in started.stream { break }
        await model.setFilter("status", value: "completed")
        #expect(model.page?.items.map(\.id) == ["done"] && model.query == "Follow")
        finish?.resume(returning: try response(ids: ["old-scroll"], page: 2))
        await scrolling.value
        #expect(model.page?.items.map(\.id) == ["done"] && model.page?.page == 1)
        #expect(model.filters == ["status": "completed"] && !model.busy)
        await model.load(filters: [:])
        #expect(model.page?.items.map(\.id) == ["open"] && model.filters.isEmpty)
    }

    @Test func supersededSearchFailureCannotClearNewResults() async throws {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Error>?
        let model = AtlasBusiness(resource: .accounts) { action in
            if action["query"] as? String == "old" {
                return try await withCheckedThrowingContinuation { finish = $0; started.continuation.yield(()) }
            }
            return try response(ids: ["new"], page: 1)
        }
        let old = Task { await model.load(query: "old") }
        for await _ in started.stream { break }
        await model.load(query: "new")
        finish?.resume(throwing: AtlasAuthenticationError(kind: "forbidden", message: "Old error"))
        await old.value
        #expect(model.query == "new" && model.page?.items.map(\.id) == ["new"])
        #expect(!model.forbidden && model.errorMessage == nil && !model.busy)
    }

    private func response(ids: [String], page: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "items": ids.map { ["id": $0, "fields": ["title": $0], "can_edit": true, "can_delete": true] },
            "page": page, "total_pages": 2, "total_count": 3, "can_write": true, "summary": [],
            "options": ["users": [], "accounts": [], "segments": [], "statuses": [], "deal_stages": []]
        ])
    }
}
