import ActivityKit
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AtlasOrbitLiveActivity {
    typealias Request = ([String: Any]) async throws -> Data
    private struct Status: Decodable {
        let available: Bool
        let content: AtlasActivityAttributes.ContentState
    }

    private var request: Request?
    private var server: URL?
    private var activity: Activity<AtlasActivityAttributes>?
    private var generation = UUID()
    private var active = false
    private var dismissedWork: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private var refreshIdentity = UUID()
    private var refreshAgain = false
    private var loop: Task<Void, Never>?
    private var tokens: Task<Void, Never>?
    private var states: Task<Void, Never>?
    private var registration: Task<Void, Never>?
    private var pendingToken: Data?
    private var registeredToken: Data?
    private var lastRefresh = Date.distantPast

    func configure(server: URL?, request: Request?) async {
        invalidate()
        self.server = server
        self.request = request
        dismissedWork = []
        // Never adopt another signed-in session's activity after a cold launch.
        let existing = Activity<AtlasActivityAttributes>.activities
        for previous in existing {
            await previous.end(nil, dismissalPolicy: .immediate)
            if previous.attributes.server == server?.absoluteString, let request {
                _ = try? await request(["action": "unregister", "registration_id": previous.attributes.registrationID])
            }
        }
        if active { startLoop() }
    }

    func setActive(_ value: Bool) {
        active = value
        loop?.cancel()
        loop = nil
        if value {
            startLoop()
        } else {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    func refresh() {
        guard active, request != nil else { return }
        refreshAgain = true
        guard refreshTask == nil else { return }
        let identity = generation
        let refreshID = UUID()
        refreshIdentity = refreshID
        refreshTask = Task {
            defer { if refreshIdentity == refreshID { refreshTask = nil } }
            while refreshAgain, generation == identity, !Task.isCancelled {
                refreshAgain = false
                let delay = max(0, 2 - Date().timeIntervalSince(lastRefresh))
                do {
                    try await Task.sleep(for: .seconds(delay))
                    try Task.checkCancellation()
                    lastRefresh = Date()
                    await reconcile(identity: identity)
                } catch { return }
            }
        }
    }

    func signOut() async {
        let previous = activity
        let cleanup = request
        invalidate()
        if let previous {
            await previous.end(nil, dismissalPolicy: .immediate)
            if let cleanup {
                _ = try? await cleanup(["action": "unregister", "registration_id": previous.attributes.registrationID])
            }
        }
        server = nil
        request = nil
    }

    func invalidate() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        loop?.cancel()
        loop = nil
        tokens?.cancel()
        states?.cancel()
        tokens = nil
        states = nil
        registration?.cancel()
        registration = nil
        pendingToken = nil
        registeredToken = nil
        request = nil
        server = nil
        if let previous = activity {
            activity = nil
            Task { await previous.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func startLoop() {
        guard request != nil, loop == nil else { return }
        refresh()
        loop = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                refresh()
            }
        }
    }

    private func reconcile(identity: UUID) async {
        guard let request, let server else { return }
        do {
            let data = try await request(["action": "status"])
            let status = try JSONDecoder().decode(Status.self, from: data)
            guard generation == identity, active, !Task.isCancelled else { return }
            let state = status.content
            if !status.available || state.isEmpty {
                dismissedWork = []
                await finish(using: request)
                return
            }
            let work = Set(state.conversations.map { "\($0.id):\($0.startedAt)" })
            dismissedWork.formIntersection(work)
            guard !work.isSubset(of: dismissedWork) else { return }
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
            if let activity {
                await activity.update(content)
                if let pendingToken, registeredToken != pendingToken {
                    register(pendingToken, activity: activity, identity: identity)
                }
            } else if ActivityAuthorizationInfo().areActivitiesEnabled,
                      UIApplication.shared.applicationState == .active {
                let attributes = AtlasActivityAttributes(
                    registrationID: UUID().uuidString.lowercased(), server: server.absoluteString
                )
                let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
                self.activity = activity
                pendingToken = nil
                registeredToken = nil
                observe(activity, identity: identity)
            }
        } catch let failure as AtlasAuthenticationError
            where ["sign_in_required", "unsupported_client", "unavailable"].contains(failure.kind) {
            if generation == identity { await finish(using: request) }
        } catch {
            // Keep the last authorized state until its stale date; never invent progress.
        }
    }

    private func finish(using request: @escaping Request) async {
        guard let activity else { return }
        self.activity = nil
        tokens?.cancel()
        states?.cancel()
        pendingToken = nil
        registeredToken = nil
        await activity.end(nil, dismissalPolicy: .immediate)
        _ = try? await request(["action": "unregister", "registration_id": activity.attributes.registrationID])
    }

    private func observe(_ activity: Activity<AtlasActivityAttributes>, identity: UUID) {
        tokens?.cancel()
        states?.cancel()
        tokens = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard let self, generation == identity, self.activity?.id == activity.id, !Task.isCancelled else { return }
                pendingToken = token
                register(token, activity: activity, identity: identity)
            }
        }
        states = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, generation == identity, self.activity?.id == activity.id, !Task.isCancelled else { return }
                if state == .dismissed || state == .ended {
                    if state == .dismissed {
                        dismissedWork = Set(activity.content.state.conversations.map { "\($0.id):\($0.startedAt)" })
                    }
                    self.activity = nil
                    pendingToken = nil
                    registeredToken = nil
                    tokens?.cancel()
                    if let request {
                        _ = try? await request(["action": "unregister", "registration_id": activity.attributes.registrationID])
                    }
                    return
                }
            }
        }
    }

    private func register(_ token: Data, activity: Activity<AtlasActivityAttributes>, identity: UUID) {
        guard let request, let environment = Self.environment else { return }
        let previous = registration
        registration = Task {
            await previous?.value
            guard generation == identity, self.activity?.id == activity.id, !Task.isCancelled else { return }
            do {
                _ = try await request([
                    "action": "register", "registration_id": activity.attributes.registrationID,
                    "token": token.map { String(format: "%02x", $0) }.joined(), "environment": environment
                ])
                if generation == identity, self.activity?.id == activity.id { registeredToken = token }
            } catch let failure as AtlasAuthenticationError
                where ["conflict", "sign_in_required", "unsupported_client", "unavailable"].contains(failure.kind) {
                if generation == identity, self.activity?.id == activity.id { await finish(using: request) }
            } catch { return }
        }
    }

    private static var environment: String? {
        switch Bundle.main.object(forInfoDictionaryKey: "AtlasPushEnvironment") as? String {
        case "development": "sandbox"
        case "production": "production"
        default: nil
        }
    }
}

private struct AtlasLiveActivityKey: EnvironmentKey {
    static let defaultValue: AtlasOrbitLiveActivity? = nil
}

extension EnvironmentValues {
    var atlasLiveActivity: AtlasOrbitLiveActivity? {
        get { self[AtlasLiveActivityKey.self] }
        set { self[AtlasLiveActivityKey.self] = newValue }
    }
}
