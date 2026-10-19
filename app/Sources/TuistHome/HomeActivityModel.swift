import Foundation
import Observation
import OpenAPIRuntime
import TuistAuthentication
import TuistHTTP
import TuistProjects
import TuistServer

@MainActor
@Observable
public final class HomeActivityModel {
    public let projectContext: ProjectContext
    public var authenticationError: Error? {
        guard loadedFullHandle == projectContext.selectedFullHandle else { return nil }
        return loadedAuthenticationError
    }

    private var loadedAuthenticationError: Error?
    private let service: HomeActivityFetching
    private let serverURL: URL
    private let credentialsStore: ServerCredentialsStoring
    private let cachedValueStore: CachedValueStoring
    private var sections: [HomeActivityKind: HomeActivitySection] = [:]
    private var loadedFullHandle: String?
    private var requestID = UUID()
    private var hasLoaded = false

    public init(
        projectContext: ProjectContext,
        service: HomeActivityFetching = HomeActivityService(),
        serverURL: URL = AppServerEnvironmentService().url()
    ) {
        self.projectContext = projectContext
        self.service = service
        self.serverURL = serverURL
        credentialsStore = ServerCredentialsStore.current
        cachedValueStore = CachedValueStore.current
    }

    public func section(_ kind: HomeActivityKind) -> HomeActivitySection {
        guard loadedFullHandle == projectContext.selectedFullHandle else {
            var section = HomeActivitySection()
            section.isLoading = true
            return section
        }
        return sections[kind] ?? HomeActivitySection()
    }

    public func load(force: Bool = false) async {
        let handle = projectContext.selectedFullHandle
        guard force || !hasLoaded || loadedFullHandle != handle else { return }
        requestID = UUID()
        let request = requestID
        if loadedFullHandle != handle { sections = [:] }
        loadedFullHandle = handle
        hasLoaded = false
        loadedAuthenticationError = nil
        for kind in HomeActivityKind.allCases {
            sections[kind, default: HomeActivitySection()].isLoading = false
        }
        guard let handle else { return }

        async let builds: Void = loadSection(.buildFailures, fullHandle: handle, request: request)
        async let tests: Void = loadSection(.testFailures, fullHandle: handle, request: request)
        async let flakes: Void = loadSection(.flakyTests, fullHandle: handle, request: request)
        _ = await (builds, tests, flakes)
        if isCurrent(request, fullHandle: handle) { hasLoaded = true }
    }

    public func retry(_ kind: HomeActivityKind) async {
        guard let handle = projectContext.selectedFullHandle, loadedFullHandle == handle else { return }
        await loadSection(kind, fullHandle: handle, request: requestID)
    }

    private func loadSection(_ kind: HomeActivityKind, fullHandle: String, request: UUID) async {
        guard isCurrent(request, fullHandle: fullHandle), sections[kind]?.isLoading != true else { return }
        sections[kind, default: HomeActivitySection()].isLoading = true
        sections[kind, default: HomeActivitySection()].errorMessage = nil
        defer {
            if requestID == request { sections[kind, default: HomeActivitySection()].isLoading = false }
        }
        do {
            let items = try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                try await CachedValueStore.$current.withValue(cachedValueStore) {
                    try await service.fetch(kind, fullHandle: fullHandle, serverURL: serverURL)
                }
            }
            guard isCurrent(request, fullHandle: fullHandle) else { return }
            sections[kind, default: HomeActivitySection()].items = Array(items.prefix(3))
            sections[kind, default: HomeActivitySection()].hasLoaded = true
        } catch {
            guard isCurrent(request, fullHandle: fullHandle), !(error is CancellationError) else { return }
            sections[kind, default: HomeActivitySection()].errorMessage = (error as? HomeActivityError)?.localizedDescription
                ?? "Couldn't load activity. Check your connection and try again."
            if error is ClientAuthenticationError {
                loadedAuthenticationError = error
            } else if let clientError = error as? ClientError, clientError.underlyingError is ClientAuthenticationError {
                loadedAuthenticationError = clientError.underlyingError
            }
        }
    }

    private func isCurrent(_ request: UUID, fullHandle: String) -> Bool {
        requestID == request && projectContext.selectedFullHandle == fullHandle && !Task.isCancelled
    }
}
