import Foundation
import Observation
import TuistAuthentication
import TuistLogging
import TuistServer

/// A flag the server turns on per user. The raw value is the name the server returns.
public enum FeatureFlag: String, CaseIterable, Sendable {
    /// AI features, such as connecting Claude and ChatGPT subscriptions.
    case ai
}

/// The feature flags enabled for the signed-in user. The app injects one instance with
/// `.environment(_:)`, and views read it with `@Environment(FeatureFlags.self)`, so they update
/// when a refresh changes the flags. Flags are off until the server turns them on.
@MainActor
@Observable
public final class FeatureFlags {
    public private(set) var enabled: Set<FeatureFlag>

    @ObservationIgnored private let service: ListFeatureFlagsServicing
    @ObservationIgnored private let serverURL: () -> URL
    /// The session `enabled` belongs to.
    @ObservationIgnored private var session: AuthenticationState?
    /// Counts refreshes, so only the latest one applies its response.
    @ObservationIgnored private var generation = 0

    public init(
        enabled: Set<FeatureFlag> = [],
        service: ListFeatureFlagsServicing = ListFeatureFlagsService(),
        serverURL: @escaping () -> URL = { AppServerEnvironmentService().url() }
    ) {
        self.enabled = enabled
        self.service = service
        self.serverURL = serverURL
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabled.contains(flag)
    }

    /// Fetches the flags for `state`. Call on launch, when the session changes, and when the app returns to the
    /// foreground. Signing out or switching accounts turns every flag off. A failed fetch keeps the session's last
    /// flags, so features don't disappear while offline.
    public func refresh(for state: AuthenticationState) async {
        generation += 1
        let current = generation
        guard case .loggedIn = state else {
            session = nil
            enabled = []
            return
        }
        if session != state {
            session = state
            enabled = []
        }
        do {
            let names = try await service.listFeatureFlags(serverURL: serverURL())
            // A later refresh, possibly for another session, started while the request was in flight.
            guard generation == current else { return }
            enabled = Set(names.compactMap(FeatureFlag.init(rawValue:)))
        } catch {
            Logger.current.error("Failed to fetch the feature flags: \(error.localizedDescription)")
        }
    }
}
