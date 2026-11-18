import SwiftUI

#if os(iOS)
    /// One first breath per ready residency. The decoration never intercepts a touch,
    /// and stops drawing after four seconds rather than running an idle animation.
    struct SandboxReadyEffect: View {
        let residency: String?
        @State private var started: Date?
        @State private var shown: String?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            TimelineView(.animation(paused: started == nil || reduceMotion)) { timeline in
                if let started {
                    let elapsed = max(0, timeline.date.timeIntervalSince(started))
                    let fadeIn = min(1, elapsed / 0.6)
                    let fadeOut = min(1, max(0, (4 - elapsed) / 2.5))
                    let strength = reduceMotion ? 0.6 : 0.8
                        * fadeIn * fadeIn * (3 - 2 * fadeIn)
                        * fadeOut * fadeOut * (3 - 2 * fadeOut)
                    let gradient = AngularGradient(
                        colors: [Noora.primary, .pink, .purple, .cyan, Noora.primary],
                        center: reduceMotion ? .center : UnitPoint(
                            x: 0.5 + 0.14 * sin(elapsed * 0.8),
                            y: 0.5 + 0.14 * cos(elapsed * 0.7)
                        ),
                        angle: .degrees(reduceMotion ? 0 : elapsed * 28 + 18 * sin(elapsed * 1.2))
                    )
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .strokeBorder(gradient, lineWidth: reduceMotion ? 2 : 20 + 4 * sin(elapsed * 1.5))
                        .blur(radius: reduceMotion ? 0 : 18 + 2 * cos(elapsed * 1.3))
                        .overlay {
                            if !reduceMotion {
                                RoundedRectangle(cornerRadius: 42, style: .continuous)
                                    .strokeBorder(gradient, lineWidth: 1)
                                    .blur(radius: 1.5)
                                    .opacity(0.3)
                            }
                        }
                        .padding(3)
                        .opacity(strength)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: scenePhase == .active ? residency : nil) {
                started = nil
                guard let residency, residency != shown, scenePhase == .active else { return }
                shown = residency
                started = .now
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                started = nil
            }
        }
    }

    #if targetEnvironment(simulator)
        /// A signed-out native motion fixture, like CardPreview. Its simulated event
        /// drives exactly the overlay used in ConversationView; it starts no real VM.
        struct SandboxReadyPreview: View {
            @State private var residency: String?
            @State private var waking = false
            @State private var failed = ProcessInfo.processInfo.arguments.contains("-LuftSandboxFailure")
            @State private var reply = ""
            @State private var voice = VoiceInput()
            @State private var attempt = 0
            @State private var dark = !ProcessInfo.processInfo.arguments.contains("-LuftSandboxLight")

            private var status: LocalizedStringKey {
                waking ? "Waking the sandbox…" : failed ? "Workspace unavailable" : residency == nil ? "Sandbox paused" : "Sandbox ready"
            }

            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Motion preview · simulated readiness")
                                .font(.caption).foregroundStyle(Noora.labelSecondary)
                            MessageRow(message: message("user", "Could the thread feel alive when my sandbox is ready?")) { _ in }
                            MessageRow(message: message(
                                "assistant",
                                "I’ll prepare the workspace so I can read the repository and run commands."
                            )) { _ in }
                            HStack(spacing: 8) {
                                if waking { ProgressView().controlSize(.small) }
                                Text(status).font(.subheadline).foregroundStyle(Noora.labelSecondary)
                            }
                            HStack {
                                Button("Replay startup") { failed = false; attempt += 1 }
                                Button("Try failure") { failed = true; attempt += 1 }
                            }
                            .buttonStyle(.bordered)
                            Button(dark ? "Light appearance" : "Dark appearance") { dark.toggle() }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            if residency != nil {
                                Label("Sandbox ready", systemImage: "checkmark.circle")
                                    .font(.caption).foregroundStyle(Noora.labelSecondary)
                            }
                            ReplyComposer(reply: $reply, disabled: true, sending: false, voice: voice) {}
                        }
                        .padding()
                    }
                    .background {
                        Noora.backgroundPrimary
                            .overlay { SandboxReadyEffect(residency: residency) }
                    }
                    .navigationTitle("Sandbox first breath")
                    .navigationBarTitleDisplayMode(.inline)
                    .task(id: attempt) {
                        residency = nil
                        waking = true
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        waking = false
                        if !failed { residency = UUID().uuidString }
                    }
                }
                .preferredColorScheme(dark ? .dark : .light)
            }

            private func message(_ role: String, _ content: String) -> AppMessage {
                AppMessage(id: role, role: role, content: content)
            }
        }
    #endif
#endif
