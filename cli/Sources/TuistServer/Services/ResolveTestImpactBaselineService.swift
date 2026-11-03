import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ResolveTestImpactBaselineServicing {
    /// Asks the server for the nearest full run on the platform to select tests against. Never
    /// throws: a failed or timed-out request comes back as `.failed`, and the run falls back.
    /// - Parameters:
    ///   - commitSHA: The checked-out commit.
    ///   - parentSHAs: The checked-out commit's parents, for a commit the server's history doesn't
    ///     have yet, such as a new commit or a pull request's merge commit.
    func resolveTestImpactBaseline(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        parentSHAs: [String],
        platform: String?,
        scheme: String?,
        testPlan: String?,
        destination: String?
    ) async -> TestImpactBaselineResolution
}

public struct ResolveTestImpactBaselineService: ResolveTestImpactBaselineServicing {
    private let fullHandleService: FullHandleServicing
    private let timeout: Duration

    public init(
        fullHandleService: FullHandleServicing = FullHandleService(),
        timeout: Duration = .seconds(2)
    ) {
        self.fullHandleService = fullHandleService
        self.timeout = timeout
    }

    public func resolveTestImpactBaseline(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        parentSHAs: [String],
        platform: String?,
        scheme: String?,
        testPlan: String?,
        destination: String?
    ) async -> TestImpactBaselineResolution {
        do {
            let handles = try fullHandleService.parse(fullHandle)
            let client = Client.authenticated(serverURL: serverURL)
            let input = Operations.resolveTestImpactBaseline.Input(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(.init(
                    build_system: "xcode",
                    commit_sha: commitSHA,
                    parent_shas: parentSHAs.isEmpty ? nil : parentSHAs,
                    platform: platform,
                    xcode: scheme == nil && testPlan == nil && destination == nil
                        ? nil
                        : .init(destination: destination, scheme: scheme, test_plan: testPlan)
                ))
            )
            guard let response = try await withTestImpactTimeout(timeout, { try await client.resolveTestImpactBaseline(input) })
            else {
                return .failed("The test impact baseline request didn't finish within \(timeout.components.seconds)s.")
            }
            return Self.resolution(from: response)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func resolution(from response: Operations.resolveTestImpactBaseline.Output) -> TestImpactBaselineResolution {
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(baseline):
                if let sha = baseline.baseline_sha, !sha.isEmpty {
                    return .baseline(sha: sha, diffCached: baseline.diff_cached ?? false)
                }
                let reason = baseline.reason.map(TestImpactFallbackReason.init(rawValue:))
                // An unknown reason means the same as `not_enabled` to this client.
                guard let reason, TestImpactFallbackReason.recordedBaselineReasons.contains(reason) else { return .notEnabled }
                return .unavailable(reason)
            }
        case let .badRequest(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .unauthorized(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .forbidden(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .notFound(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .tooManyRequests(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .undocumented(statusCode, _):
            return .failed("The test impact baseline request failed with an unknown Tuist response of \(statusCode).")
        }
    }
}
