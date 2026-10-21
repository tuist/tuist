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
        await model.load()
        #expect(model.forbidden && model.page == nil && model.records.isEmpty)
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
}
