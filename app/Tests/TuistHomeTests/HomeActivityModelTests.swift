import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistAppStorage
import TuistHTTP
import TuistServer

@testable import TuistHome
@testable import TuistProjects

@MainActor
struct HomeActivityModelTests {
    @Test func loads_three_independent_sections_and_bounds_rows() async throws {
        let context = try await makeContext()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, _, _ in
            (1 ... 5).map { Self.item("\(kind.rawValue)-\($0)") }
        }, serverURL: URL(string: "https://example.invalid")!)

        await subject.load()

        for kind in HomeActivityKind.allCases {
            #expect(subject.section(kind).items.count == 3)
            #expect(subject.section(kind).hasLoaded)
            #expect(!subject.section(kind).isLoading)
            #expect(subject.section(kind).errorMessage == nil)
        }
    }

    @Test func one_section_failure_does_not_hide_successful_siblings() async throws {
        let context = try await makeContext()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, _, _ in
            if kind == .flakyTests { throw HomeActivityError.unavailable }
            return [Self.item(kind.rawValue)]
        }, serverURL: URL(string: "https://example.invalid")!)

        await subject.load()

        #expect(subject.section(.buildFailures).items.map(\.id) == ["buildFailures"])
        #expect(subject.section(.testFailures).items.map(\.id) == ["testFailures"])
        #expect(subject.section(.flakyTests).errorMessage != nil)
        #expect(!subject.section(.flakyTests).hasLoaded)
    }

    @Test func project_switch_hides_old_content_and_discards_late_responses() async throws {
        let context = try await makeContext()
        let pending = PendingActivity()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, handle, _ in
            if handle == "sample/one" { return await pending.value(kind) }
            return [Self.item("new-\(kind.rawValue)")]
        }, serverURL: URL(string: "https://example.invalid")!)
        let oldTask = Task { await subject.load() }
        await pending.waitForRequests(3)

        context.selectProject("sample/two")
        #expect(subject.section(.buildFailures).items.isEmpty)
        await subject.load()
        await pending.resumeAll(with: [Self.item("old")])
        await oldTask.value

        for kind in HomeActivityKind.allCases {
            #expect(subject.section(kind).items.map(\.id) == ["new-\(kind.rawValue)"])
        }
    }

    @Test func cancellation_does_not_become_an_empty_success_or_error() async throws {
        let context = try await makeContext()
        let pending = PendingActivity()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, _, _ in
            await pending.value(kind)
        }, serverURL: URL(string: "https://example.invalid")!)
        let task = Task { await subject.load() }
        await pending.waitForRequests(3)
        task.cancel()
        await pending.resumeAll(with: [Self.item("cancelled")])
        await task.value

        for kind in HomeActivityKind.allCases {
            #expect(subject.section(kind).items.isEmpty)
            #expect(!subject.section(kind).hasLoaded)
            #expect(subject.section(kind).errorMessage == nil)
            #expect(!subject.section(kind).isLoading)
        }
    }

    @Test func successful_content_remains_visible_while_refreshing() async throws {
        let context = try await makeContext()
        let responses = RefreshActivity()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, _, _ in
            await responses.value(kind)
        }, serverURL: URL(string: "https://example.invalid")!)
        await subject.load()
        let task = Task { await subject.load(force: true) }
        await responses.pending.waitForRequests(3)

        #expect(subject.section(.buildFailures).items.map(\.id) == ["first"])
        #expect(subject.section(.buildFailures).isLoading)
        await responses.pending.resumeAll(with: [Self.item("refreshed")])
        await task.value
        #expect(subject.section(.buildFailures).items.map(\.id) == ["refreshed"])
    }

    @Test func uses_the_captured_server_and_credential_environment() async throws {
        let context = try await makeContext()
        let credentials = MockServerCredentialsStoring()
        let cache = MockCachedValueStoring()
        let subject = ServerCredentialsStore.$current.withValue(credentials) {
            CachedValueStore.$current.withValue(cache) {
                HomeActivityModel(projectContext: context, service: StubActivityService { _, _, url in
                    #expect(url.absoluteString == "https://example.invalid/tenant")
                    #expect((ServerCredentialsStore.current as AnyObject) === credentials)
                    #expect((CachedValueStore.current as AnyObject) === cache)
                    return []
                }, serverURL: URL(string: "https://example.invalid/tenant")!)
            }
        }

        await subject.load()
        #expect(subject.section(.buildFailures).hasLoaded)
    }

    @Test func authenticated_client_failures_are_scoped_to_the_current_project() async throws {
        let context = try await makeContext()
        let service = HomeActivityService(makeClient: { Client(serverURL: $0, transport: ExpiredActivityTransport()) })
        let subject = HomeActivityModel(
            projectContext: context,
            service: service,
            serverURL: URL(string: "https://example.invalid")!
        )

        await subject.load()

        #expect((subject.authenticationError as? ClientAuthenticationError) == .notAuthenticated)
        context.selectProject("sample/two")
        #expect(subject.authenticationError == nil)
    }

    @Test func stale_authentication_failures_cannot_sign_out_the_current_project() async throws {
        let context = try await makeContext()
        let pending = PendingActivity()
        let subject = HomeActivityModel(projectContext: context, service: StubActivityService { kind, handle, _ in
            if handle == "sample/one" {
                _ = await pending.value(kind)
                throw ClientAuthenticationError.notAuthenticated
            }
            return []
        }, serverURL: URL(string: "https://example.invalid")!)
        let oldTask = Task { await subject.load() }
        await pending.waitForRequests(3)
        context.selectProject("sample/two")
        await subject.load()
        await pending.resumeAll(with: [])
        await oldTask.value
        #expect(subject.authenticationError == nil)
    }

    private func makeContext() async throws -> ProjectContext {
        let projects = MockListProjectsServicing()
        let server = MockServerEnvironmentServicing()
        let storage = MockAppStoring()
        given(projects).listProjects(serverURL: .any).willReturn([
            .test(fullName: "sample/one"), .test(fullName: "sample/two"),
        ])
        given(server).url().willReturn(URL(string: "https://example.invalid")!)
        given(storage).get(.any as Parameter<ProjectSelectionsKey.Type>).willReturn([:])
        given(storage).get(.any as Parameter<RecentProjectsKey.Type>).willReturn([:])
        given(storage).set(.any as Parameter<ProjectSelectionsKey.Type>, value: .any).willReturn()
        given(storage).set(.any as Parameter<RecentProjectsKey.Type>, value: .any).willReturn()
        let context = ProjectContext(
            scope: "sample",
            listProjectsService: projects,
            serverEnvironmentService: server,
            appStorage: storage
        )
        try await context.load()
        return context
    }

    fileprivate nonisolated static func item(_ id: String) -> HomeActivityItem {
        HomeActivityItem(
            id: id,
            title: id,
            subtitle: "main",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            url: URL(string: "https://example.invalid/sample/one/tests/test-runs/\(id)")!
        )
    }
}

private struct StubActivityService: HomeActivityFetching {
    let perform: @Sendable (HomeActivityKind, String, URL) async throws -> [HomeActivityItem]

    func fetch(_ kind: HomeActivityKind, fullHandle: String, serverURL: URL) async throws -> [HomeActivityItem] {
        try await perform(kind, fullHandle, serverURL)
    }
}

private actor PendingActivity {
    private var continuations: [HomeActivityKind: CheckedContinuation<[HomeActivityItem], Never>] = [:]
    private var completedItems: [HomeActivityItem]?

    func value(_ kind: HomeActivityKind) async -> [HomeActivityItem] {
        if let completedItems { return completedItems }
        return await withCheckedContinuation { continuations[kind] = $0 }
    }

    func waitForRequests(_ count: Int) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while continuations.count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(continuations.count == count)
    }

    func resumeAll(with items: [HomeActivityItem]) {
        completedItems = items
        let waiting = continuations.values
        continuations = [:]
        for continuation in waiting {
            continuation.resume(returning: items)
        }
    }
}

private struct ExpiredActivityTransport: ClientTransport {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        throw ClientAuthenticationError.notAuthenticated
    }
}

private actor RefreshActivity {
    let pending = PendingActivity()
    private var loaded = Set<HomeActivityKind>()

    func value(_ kind: HomeActivityKind) async -> [HomeActivityItem] {
        if loaded.insert(kind).inserted { return [HomeActivityModelTests.item("first")] }
        return await pending.value(kind)
    }
}
