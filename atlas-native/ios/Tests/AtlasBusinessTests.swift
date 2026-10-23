import Foundation
import Testing

@MainActor
struct AtlasBusinessTests {
    private let recordID = "123e4567-e89b-12d3-a456-426614174000"
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

    @Test func financeOverviewSurvivesPaginationButRefreshReplacesIt() async throws {
        var cash = "123456789.13"
        let model = AtlasBusiness(resource: .invoices) { action in
            let page = action["page"] as? Int ?? 1
            var payload = try #require(JSONSerialization.jsonObject(with: response(ids: ["invoice-\(page)"], page: page))
                as? [String: Any])
            if page == 1 {
                payload["finance_overview"] = [
                    "currency": "EUR", "as_of": "2026-10-22", "account_count": 3,
                    "available_cash": cash, "monthly_burn": NSNull(), "runway_months": NSNull(),
                    "fx_published_on": "2026-10-21", "excluded_currencies": [],
                    "months": [["month": "2026-10", "income": "10.25", "expense": "27.50"]]
                ]
            }
            return try JSONSerialization.data(withJSONObject: payload)
        }
        await model.load()
        await model.loadMore()
        #expect(model.page?.items.count == 2)
        #expect(model.page?.financeOverview?.availableCash == "123456789.13")
        #expect(model.page?.financeOverview?.months.first?.expense == "27.50")
        #expect(model.page?.financeOverview?.monthlyBurn == nil)
        cash = "900.01"
        await model.load()
        #expect(model.page?.financeOverview?.availableCash == "900.01")
    }

    @Test func accountDetailsSurviveListRefreshAndAreReplacedByAuthorizedDetailResponse() async throws {
        var summary = "Authorized summary"
        let model = AtlasBusiness(resource: .accounts) { action in
            if action["action"] as? String != "show" { return try response(ids: ["account"], page: 1) }
            return try JSONSerialization.data(withJSONObject: ["item": [
                "id": "account", "can_edit": false, "can_delete": false, "fields": ["name": "Northstar"],
                "details": [
                    "fields": ["overview_summary": summary], "address": [:], "billing": [:], "signatory": [:],
                    "children": [], "contacts": [], "terms": [], "invoices": [], "documents": [],
                    "events": [], "outcomes": [], "service_levels": []
                ]
            ]])
        }
        await model.load()
        let record = try #require(model.page?.items.first)
        await model.show(record)
        await model.load()
        #expect(model.records[record.id]?.details?.fields["overview_summary"] == "Authorized summary")
        summary = "Updated summary"
        await model.show(record)
        #expect(model.records[record.id]?.details?.fields["overview_summary"] == "Updated summary")
    }

}

extension AtlasBusinessTests {
    @Test func forbiddenRecordLookupRevokesCachedDataAndCanRecover() async throws {
        var denied = false
        let item = """
        {"id":"\(recordID)","fields":{"title":"Cached task"},"can_edit":true,"can_delete":true}
        """
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["action"] as? String == "show" {
                if denied { throw AtlasAuthenticationError(kind: "forbidden", message: "Access revoked") }
                return Data("{\"item\":\(item)}".utf8)
            }
            return Data("""
            {"items":[\(item)],"page":1,"total_pages":1,"total_count":1,"can_write":true,"summary":[],
            "options":{"users":[{"id":"user","name":"Taylor"}],"accounts":[],"segments":[],"statuses":[],"deal_stages":[]}}
            """.utf8)
        }
        await model.load()
        #expect(model.page != nil && !model.records.isEmpty && !model.options.users.isEmpty)
        denied = true
        do { _ = try await model.record(id: recordID); Issue.record("Forbidden lookup succeeded") } catch {
            #expect((error as? AtlasAuthenticationError)?.kind == "forbidden")
        }
        #expect(model.forbidden && model.page == nil && model.records.isEmpty)
        #expect(model.options.users.isEmpty)
        denied = false
        _ = try await model.record(id: recordID)
        #expect(!model.forbidden && model.records[recordID] != nil)
    }

    @Test(arguments: ["list", "show"])
    func forbiddenRecordLookupInvalidatesOlderReads(action pendingAction: String) async throws {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        var holdRead = false
        let page = try response(ids: [recordID], page: 1)
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["id"] as? String == "denied" {
                throw AtlasAuthenticationError(kind: "forbidden", message: "Access revoked")
            }
            if holdRead, action["action"] as? String == pendingAction {
                return await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
            }
            return page
        }
        await model.load()
        let cached = try #require(model.page?.items.first)
        holdRead = true
        let older = Task {
            if pendingAction == "list" { await model.load() } else { await model.show(cached) }
        }
        for await _ in started.stream { break }
        do { _ = try await model.record(id: "denied"); Issue.record("Forbidden lookup succeeded") } catch {
            #expect((error as? AtlasAuthenticationError)?.kind == "forbidden")
        }
        #expect(model.forbidden && !model.busy && !model.loading)
        let detail = Data("""
        {"item":{"id":"\(recordID)","fields":{},"can_edit":true,"can_delete":true}}
        """.utf8)
        finish?.resume(returning: pendingAction == "list" ? page : detail)
        await older.value
        #expect(model.forbidden && model.page == nil && model.records.isEmpty)
    }

    @Test func cancelledRecordFailureCannotRevokeNewerListResults() async throws {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Error>?
        let model = AtlasBusiness(resource: .tasks) { action in
            if action["action"] as? String == "show" {
                return try await withCheckedThrowingContinuation { finish = $0; started.continuation.yield(()) }
            }
            return try response(ids: [recordID], page: 1)
        }
        let lookup = Task { try await model.record(id: recordID) }
        for await _ in started.stream { break }
        lookup.cancel()
        await model.load()
        finish?.resume(throwing: AtlasAuthenticationError(kind: "forbidden", message: "Old error"))
        do { _ = try await lookup.value; Issue.record("Cancelled lookup succeeded") } catch is CancellationError {}
        #expect(!model.forbidden && model.page != nil && model.records[recordID] != nil)
    }

    private func response(ids: [String], page: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "items": ids.map { ["id": $0, "fields": ["title": $0], "can_edit": true, "can_delete": true] },
            "page": page, "total_pages": 2, "total_count": 3, "can_write": true, "summary": [],
            "options": ["users": [], "accounts": [], "segments": [], "statuses": [], "deal_stages": []]
        ])
    }
}
