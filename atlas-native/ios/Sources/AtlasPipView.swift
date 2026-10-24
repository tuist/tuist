import Foundation
import SwiftUI

struct AtlasPipReaction {
    enum Expression: String, CaseIterable {
        case neutral = "PipNeutral"
        case wave = "PipWave"
        case curious = "PipCurious"
        case delighted = "PipDelighted"
        case surprised = "PipSurprised"
        case affectionate = "PipAffectionate"

        var description: String {
            switch self {
            case .neutral: "Ready to help"
            case .wave: "Waving hello"
            case .curious: "Feeling curious"
            case .delighted: "Jumping for joy"
            case .surprised: "A little surprised"
            case .affectionate: "Sending a little love"
            }
        }
    }

    private(set) var expression = Expression.neutral
    private(set) var intensity = 0.0
    private(set) var burstCount = 0
    private var lastActivation: TimeInterval?
    private var alternateGreeting = false

    mutating func activate(at time: TimeInterval, pressDuration: TimeInterval = 0) {
        let interval = lastActivation.map { time - $0 }
        burstCount = interval.map { (0...0.65).contains($0) } == true ? min(burstCount + 1, 5) : 1
        lastActivation = time
        alternateGreeting.toggle()

        // Touch duration and tap cadence are playful cues, not a measurement of force.
        let duration = pressDuration.isFinite ? min(max(pressDuration, 0), 1) : 0
        intensity = min(1, duration + Double(burstCount - 1) * 0.2)
        if duration >= 0.65 || burstCount == 5 {
            expression = .affectionate
        } else if intensity >= 0.55 {
            expression = .surprised
        } else if intensity >= 0.35 {
            expression = .delighted
        } else if burstCount == 2 {
            expression = .curious
        } else {
            expression = alternateGreeting ? .wave : .curious
        }
    }

    mutating func settle() {
        expression = .neutral
        intensity = 0
    }
}

struct AtlasPipView: View {
    var interactive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var reaction = AtlasPipReaction()
    @State private var reactionSequence = 0
    @State private var isPressed = false
    @State private var pressedAt: TimeInterval?
    @State private var releasedPress: (time: TimeInterval, duration: TimeInterval)?

    var body: some View {
        Group {
            if interactive {
                Button(action: activate) {
                    mascot
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PipPressStyle(pressChanged: pressChanged))
                .accessibilityLabel("Pip")
                .accessibilityValue(reaction.expression.description)
                .accessibilityHint("Say hello. Touch longer or tap a few times for a different reaction.")
                .accessibilityAction(named: "Say hello") { activate() }
                .accessibilityIdentifier("pip-mascot")
            } else {
                mascot.accessibilityHidden(true)
            }
        }
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .task(id: reactionSequence) {
            guard reactionSequence > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(1.8))
                try Task.checkCancellation()
                reaction.settle()
            } catch { }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                isPressed = false
                pressedAt = nil
                releasedPress = nil
                reaction.settle()
            }
        }
    }

    private var mascot: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
            let bob = reduceMotion || scenePhase != .active ? 0 : sin(phase * .pi * 2)
            Image(reaction.expression.rawValue)
                .resizable()
                .scaledToFit()
                .offset(y: bob * 3)
                .rotationEffect(.degrees(bob * 1.5))
                .scaleEffect(reduceMotion || !isPressed ? 1 : 0.94)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
                .accessibilityHidden(true)
        }
        .aspectRatio(1, contentMode: .fit)
        .phaseAnimator([0.0, 1.0, -0.45, 0.0], trigger: reactionSequence) { content, phase in
            let movement = reduceMotion || scenePhase != .active ? 0 : phase * (0.45 + reaction.intensity * 0.55)
            content
                .scaleEffect(x: 1 + movement * 0.12, y: 1 - movement * 0.1, anchor: .bottom)
                .rotationEffect(.degrees(movement * 9))
                .offset(y: -abs(movement) * 12)
        } animation: { _ in
            .spring(duration: 0.24, bounce: 0.35)
        }
    }

    private func pressChanged(_ pressed: Bool) {
        isPressed = pressed
        let now = ProcessInfo.processInfo.systemUptime
        if pressed {
            pressedAt = now
            releasedPress = nil
        } else if let start = pressedAt {
            releasedPress = (now, max(0, now - start))
            pressedAt = nil
        }
    }

    private func activate() {
        let now = ProcessInfo.processInfo.systemUptime
        let duration: TimeInterval
        if let start = pressedAt {
            duration = max(0, now - start)
        } else if let release = releasedPress, (0...0.15).contains(now - release.time) {
            duration = release.duration
        } else {
            duration = 0
        }
        pressedAt = nil
        releasedPress = nil
        reaction.activate(at: now, pressDuration: duration)
        reactionSequence += 1
    }
}

private struct PipPressStyle: ButtonStyle {
    let pressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        // Observe the native button instead of adding a gesture that competes with scrolling.
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in pressChanged(pressed) }
    }
}

struct AtlasPipWelcome: View {
    let prompt: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let suggestions = [
        "What needs my attention?",
        "Summarize my open tasks",
        "Find an account"
    ]

    var body: some View {
        VStack(spacing: 16) {
            AtlasPipView()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 144 : 160, height: dynamicTypeSize.isAccessibilitySize ? 144 : 160)

            VStack(spacing: 8) {
                Text("Meet Pip")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your Atlas companion. Ask a question or work out your next step.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Tap Pip to say hello. Try a longer touch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { prompt(suggestion) } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds this suggestion to your draft. Does not send a message.")
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var columns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 140), spacing: 10)]
    }
}
