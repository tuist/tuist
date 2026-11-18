import Foundation
#if os(iOS)
    import ActivityKit
#endif

/// The platform side of the threads Live Activity: starting it, handing its
/// ActivityKit push token to the core (`live_activity_register`) and ending it.
/// The server pushes everything it shows (see `ios/LiveActivity`), so the app
/// never updates its content. iOS only lets the app start an activity while
/// it's in the foreground, so it starts one when the app sees a thread working
/// and none is running for the active profile. One profile's activity ends
/// when another becomes active or it signs out. macOS has no Live Activities.
@MainActor
final class ThreadLiveActivity {
    static let shared = ThreadLiveActivity()

    #if os(iOS)
        private var client: AppClient?
        private var observed: Set<String> = []
        /// The server predates Live Activities: don't start any until the app restarts.
        private var unavailable = false

        /// Called once the core booted. Picks up activities that outlived the
        /// last launch, so their tokens are registered again.
        func attach(_ client: AppClient) {
            self.client = client
            profileChanged()
        }

        /// Ends the activities of profiles other than the active one, and keeps
        /// watching the active profile's.
        func profileChanged() {
            let active = client?.view.active?.id
            for activity in Activity<GuildActivityAttributes>.activities {
                guard [.active, .stale].contains(activity.activityState) else { continue }
                if activity.attributes.profileID == active {
                    observe(activity)
                } else {
                    end(activity, unregister: true)
                }
            }
        }

        /// Called whenever the app sees one of the active profile's threads working.
        func threadsWorking() {
            guard !unavailable, let profile = client?.view.active, PushNotifications.environment != nil,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            profileChanged()
            let running = Activity<GuildActivityAttributes>.activities.contains {
                $0.attributes.profileID == profile.id && [.active, .stale].contains($0.activityState)
            }
            guard !running else { return }
            let attributes = GuildActivityAttributes(
                registrationID: UUID().uuidString.lowercased(), profileID: profile.id, server: profile.server
            )
            let content = ActivityContent(state: GuildActivityAttributes.ContentState.starting,
                                          staleDate: Date().addingTimeInterval(120))
            guard let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token)
            else { return }
            observe(activity)
        }

        /// Before signing out: the server would otherwise keep pushing until the sign-in ends.
        func signOut() async {
            for activity in Activity<GuildActivityAttributes>.activities
                where activity.attributes.profileID == client?.view.active?.id
            {
                await unregister(activity)
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        private func observe(_ activity: Activity<GuildActivityAttributes>) {
            guard observed.insert(activity.id).inserted else { return }
            Task { [weak self] in
                for await token in activity.pushTokenUpdates {
                    await self?.register(activity, token: token)
                }
            }
            Task { [weak self] in
                for await state in activity.activityStateUpdates where state == .dismissed {
                    // Swiped away: the server needn't keep it up to date.
                    await self?.unregister(activity)
                }
            }
        }

        private func register(_ activity: Activity<GuildActivityAttributes>, token: Data) async {
            guard let client, let environment = PushNotifications.environment,
                  client.view.active?.id == activity.attributes.profileID else { return }
            let data = try? await client.call("live_activity_register", [
                "id": activity.attributes.registrationID,
                "token": token.map { String(format: "%02x", $0) }.joined(),
                "environment": environment,
            ])
            switch data?["reason"] as? String {
            case "unavailable":
                unavailable = true
                await activity.end(nil, dismissalPolicy: .immediate)
            case "retired":
                // The server won't update this one again; the next working thread starts another.
                await activity.end(nil, dismissalPolicy: .immediate)
            default:
                break
            }
        }

        private func unregister(_ activity: Activity<GuildActivityAttributes>) async {
            _ = try? await client?.call("live_activity_unregister", [
                "id": activity.attributes.registrationID, "profile_id": activity.attributes.profileID,
            ])
        }

        private func end(_ activity: Activity<GuildActivityAttributes>, unregister: Bool) {
            Task {
                if unregister { await self.unregister(activity) }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    #else
        func attach(_: AppClient) {}
        func profileChanged() {}
        func threadsWorking() {}
        func signOut() async {}
    #endif
}
