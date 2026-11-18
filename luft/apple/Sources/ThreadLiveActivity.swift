import Foundation
#if os(iOS)
    import ActivityKit
#endif

/// The platform side of the threads Live Activity: starting it, handing its
/// ActivityKit push token to the core (`live_activity_register`) and ending it.
/// The server pushes everything it shows (see `ios/LiveActivity`), so the app
/// never updates its content. iOS only lets the app start an activity while
/// it's in the foreground, so it starts one when the app sees a thread working
/// and none is running for the active profile. On iOS 17.2 and later the app
/// also hands the core its push-to-start token (`live_activity_starter_register`),
/// so the server starts the activity for threads started anywhere; iOS wakes
/// the app in the background, where the app delegate boots the core, to
/// register the activity it started.
/// Each profile shows one activity. Finished ones still lingering on the Lock
/// Screen go as soon as another appears; of two running ones (the app and the
/// server starting one at the same moment), the one registered last stays,
/// which is also the one the server keeps. One profile's activity and
/// push-to-start token go when another profile becomes active or it signs out.
/// macOS has no Live Activities.
@MainActor
final class ThreadLiveActivity {
    static let shared = ThreadLiveActivity()

    #if os(iOS)
        private var client: AppClient?
        private var observed: Set<String> = []
        /// The server predates Live Activities: don't start any until the app restarts.
        private var unavailable = false
        /// Activities being ended, which nothing hands the profile back to.
        private var dismissing: Set<String> = []
        /// The latest push-to-start token, registered again for each active profile.
        private var startToken: Data?
        /// The profile and token last registered, so seeing threads work doesn't repeat it.
        private var registeredStarter: (profile: String, token: String)?

        /// Called once the core booted. Picks up activities that outlived the
        /// last launch, so their tokens are registered again, and watches for
        /// push-to-start tokens and the activities the server starts.
        func attach(_ client: AppClient) {
            guard self.client == nil else { return }
            self.client = client
            profileChanged()
            Task { [weak self] in
                for await activity in Activity<LuftActivityAttributes>.activityUpdates {
                    self?.adopt(activity)
                }
            }
            if #available(iOS 17.2, *) {
                Task { [weak self] in
                    for await token in Activity<LuftActivityAttributes>.pushToStartTokenUpdates {
                        self?.startToken = token
                        await self?.registerStarter()
                    }
                }
            }
        }

        /// Ends the activities of profiles other than the active one, keeps
        /// watching the active profile's, and moves the push-to-start token to it.
        func profileChanged() {
            for activity in Activity<LuftActivityAttributes>.activities {
                adopt(activity)
            }
            Task { await registerStarter() }
        }

        /// Watches `activity` when it belongs to the active profile, and
        /// dismisses the profile's finished ones still on the Lock Screen.
        /// Running ones go once one of them registers (see `register`).
        private func adopt(_ activity: Activity<LuftActivityAttributes>) {
            guard [.active, .stale].contains(activity.activityState), !dismissing.contains(activity.id)
            else { return }
            let profile = activity.attributes.profileID
            guard profile == client?.view.active?.id else {
                end(activity, unregister: true)
                // Started by a server this device no longer listens to as that profile.
                Task { await unregisterStarter(profile) }
                return
            }
            for other in Activity<LuftActivityAttributes>.activities
                where other.attributes.profileID == profile && ![.active, .stale].contains(other.activityState)
            {
                end(other, unregister: false)
            }
            observe(activity)
        }

        private func registerStarter() async {
            guard !unavailable, let client, let token = startToken, let profile = client.view.active?.id,
                  let environment = PushNotifications.environment else { return }
            let hex = token.map { String(format: "%02x", $0) }.joined()
            if let previous = registeredStarter {
                guard previous.profile != profile || previous.token != hex else { return }
                // A server only moves the token between its own sign-ins.
                if previous.profile != profile { await unregisterStarter(previous.profile) }
            }
            registeredStarter = (profile, hex)
            let data = try? await client.call("live_activity_starter_register", [
                "token": hex, "environment": environment,
            ])
            // The request failed: try again the next time the app sees threads working.
            if data == nil, registeredStarter?.profile == profile, registeredStarter?.token == hex { registeredStarter = nil }
        }

        private func unregisterStarter(_ profile: String) async {
            _ = try? await client?.call("live_activity_starter_unregister", ["profile_id": profile])
        }

        /// Called whenever the app sees one of the active profile's threads working.
        func threadsWorking() {
            guard !unavailable, let profile = client?.view.active, PushNotifications.environment != nil,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            profileChanged()
            let running = Activity<LuftActivityAttributes>.activities.contains {
                $0.attributes.profileID == profile.id && [.active, .stale].contains($0.activityState)
                    && !dismissing.contains($0.id)
            }
            guard !running else { return }
            let attributes = LuftActivityAttributes(
                registrationID: UUID().uuidString.lowercased(), profileID: profile.id, server: profile.server
            )
            let content = ActivityContent(state: LuftActivityAttributes.ContentState.starting,
                                          staleDate: Date().addingTimeInterval(120))
            guard let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token)
            else { return }
            adopt(activity)
        }

        /// Before signing out: the server would otherwise keep pushing and
        /// starting activities until the sign-in ends.
        func signOut() async {
            guard let profile = client?.view.active?.id else { return }
            await unregisterStarter(profile)
            for activity in Activity<LuftActivityAttributes>.activities where activity.attributes.profileID == profile {
                dismissing.insert(activity.id)
                await unregister(activity)
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            // Only now: a profile change while signing out would otherwise register the token again.
            if registeredStarter?.profile == profile { registeredStarter = nil }
        }

        private func observe(_ activity: Activity<LuftActivityAttributes>) {
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

        private func register(_ activity: Activity<LuftActivityAttributes>, token: Data) async {
            guard let client, let environment = PushNotifications.environment, !dismissing.contains(activity.id),
                  client.view.active?.id == activity.attributes.profileID else { return }
            let data = try? await client.call("live_activity_register", [
                "id": activity.attributes.registrationID,
                "token": token.map { String(format: "%02x", $0) }.joined(),
                "environment": environment,
            ])
            switch data?["reason"] as? String {
            case "unavailable":
                unavailable = true
                end(activity, unregister: false)
            case "retired":
                // The server won't update this one again; the next working thread starts another.
                end(activity, unregister: false)
            default:
                // The server keeps the registration it saw last, so the app does too.
                guard data?["registered"] as? Bool == true, !dismissing.contains(activity.id) else { return }
                for other in Activity<LuftActivityAttributes>.activities
                    where other.id != activity.id && other.attributes.profileID == activity.attributes.profileID
                {
                    end(other, unregister: [.active, .stale].contains(other.activityState))
                }
            }
        }

        private func unregister(_ activity: Activity<LuftActivityAttributes>) async {
            _ = try? await client?.call("live_activity_unregister", [
                "id": activity.attributes.registrationID, "profile_id": activity.attributes.profileID,
            ])
        }

        private func end(_ activity: Activity<LuftActivityAttributes>, unregister: Bool) {
            guard dismissing.insert(activity.id).inserted else { return }
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
