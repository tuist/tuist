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
            case .delighted: "Happy to see you"
            case .surprised: "A little surprised"
            case .affectionate: "A warm hello"
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

struct AtlasPipPose: Equatable, Sendable {
    var bodyAngle = 0.0
    var bodyDrop = 0.0
    var armAngle = -100.0
    var leftFootAngle = 0.0
    var rightFootAngle = 0.0

    static let rest = AtlasPipPose()

    func interpolated(to other: Self, progress: Double) -> Self {
        let t = progress * progress * (3 - 2 * progress)
        return Self(
            bodyAngle: bodyAngle + (other.bodyAngle - bodyAngle) * t,
            bodyDrop: bodyDrop + (other.bodyDrop - bodyDrop) * t,
            armAngle: armAngle + (other.armAngle - armAngle) * t,
            leftFootAngle: leftFootAngle + (other.leftFootAngle - leftFootAngle) * t,
            rightFootAngle: rightFootAngle + (other.rightFootAngle - rightFootAngle) * t
        )
    }
}

enum AtlasPipMotion {
    static let duration = 2.4

    static func pose(at elapsed: TimeInterval, intensity: Double = 0, from initial: AtlasPipPose = .rest) -> AtlasPipPose {
        guard elapsed.isFinite else { return .rest }
        let strength = 1 + (intensity.isFinite ? min(1, max(0, intensity)) : 0) * 0.35
        // The torso acknowledges the greeting while ankles transfer weight and
        // the arm leads, waves, overshoots on return, then settles at the shoulder.
        let frames: [(Double, AtlasPipPose)] = [
            (0, initial),
            (0.16, AtlasPipPose(bodyAngle: -1, bodyDrop: 3 * strength, armAngle: -108, leftFootAngle: -1.2)),
            (0.28, AtlasPipPose(bodyAngle: 0.5, bodyDrop: 1, armAngle: -70)),
            (0.46, AtlasPipPose(bodyAngle: 1.8 * strength, armAngle: -14 * strength, rightFootAngle: 1)),
            (0.70, AtlasPipPose(bodyAngle: 1, bodyDrop: 0.8, armAngle: 16 * strength, rightFootAngle: 0.8)),
            (0.94, AtlasPipPose(bodyAngle: 1.2, bodyDrop: 1.8, armAngle: -18 * strength, rightFootAngle: 0.4)),
            (1.18, AtlasPipPose(bodyAngle: 0.5, bodyDrop: 0.8, armAngle: 13 * strength)),
            (1.42, AtlasPipPose(bodyAngle: 0.2, armAngle: -12 * strength)),
            (1.80, AtlasPipPose(bodyAngle: -0.8, bodyDrop: 1, armAngle: -82)),
            (2.10, AtlasPipPose(bodyAngle: 0.4, bodyDrop: 0.3, armAngle: -102)),
            (duration, .rest)
        ]
        guard elapsed > 0 else { return initial }
        for index in 1..<frames.count where elapsed <= frames[index].0 {
            let previous = frames[index - 1]
            let next = frames[index]
            return previous.1.interpolated(to: next.1, progress: (elapsed - previous.0) / (next.0 - previous.0))
        }
        return .rest
    }

    static func eyeOpenness(at elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite, elapsed >= 0 else { return 1 }
        let phase = elapsed.truncatingRemainder(dividingBy: 5.6)
        switch phase {
        case 5..<5.12: return 1 - smooth((phase - 5) / 0.12)
        case 5.12..<5.18: return 0
        case 5.18..<5.36: return smooth((phase - 5.18) / 0.18)
        default: return 1
        }
    }

    private static func smooth(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

struct AtlasPipView: View {
    var interactive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var reaction = AtlasPipReaction()
    @State private var reactionSequence = 0
    @State private var motionStartedAt: Date?
    @State private var initialPose = AtlasPipPose.rest
    @State private var idleStartedAt = Date()
    @State private var pressedAt: TimeInterval?
    @State private var releasedPress: (time: TimeInterval, duration: TimeInterval)?

    var body: some View {
        Group {
            if interactive {
                Button { activate() } label: {
                    mascot
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PipPressStyle(pressChanged: pressChanged))
                .accessibilityLabel("Pip")
                .accessibilityValue(reaction.expression.description)
                .accessibilityHint("Say hello. Touch longer or tap a few times for a different reaction.")
                .accessibilityAction(named: "Say hello") { activate(usingTouch: false) }
                .accessibilityIdentifier("pip-mascot")
            } else {
                mascot.accessibilityHidden(true)
            }
        }
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .task(id: reactionSequence) {
            guard reaction.expression != .neutral, scenePhase == .active else { return }
            do {
                try await Task.sleep(for: .seconds(AtlasPipMotion.duration))
                try Task.checkCancellation()
                reaction.settle()
                motionStartedAt = nil
                initialPose = .rest
            } catch { }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                idleStartedAt = Date()
            } else {
                stopGreeting()
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            motionStartedAt = nil
            initialPose = .rest
        }
        .onDisappear(perform: stopGreeting)
    }

    private var mascot: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            if reduceMotion {
                Image(reaction.expression.rawValue).resizable().scaledToFit()
            } else {
                let pose = motionStartedAt.map {
                    AtlasPipMotion.pose(at: timeline.date.timeIntervalSince($0), intensity: reaction.intensity, from: initialPose)
                } ?? .rest
                let eyes = scenePhase == .active ? AtlasPipMotion.eyeOpenness(at: timeline.date.timeIntervalSince(idleStartedAt)) : 1
                PipRig(pose: pose, eyeOpenness: eyes)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func pressChanged(_ pressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if pressed {
            pressedAt = now
            releasedPress = nil
        } else if let start = pressedAt {
            releasedPress = (now, max(0, now - start))
            pressedAt = nil
        }
    }

    private func activate(usingTouch: Bool = true) {
        guard scenePhase == .active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let duration: TimeInterval
        if usingTouch, let start = pressedAt {
            duration = max(0, now - start)
        } else if usingTouch, let release = releasedPress, (0...0.15).contains(now - release.time) {
            duration = release.duration
        } else {
            duration = 0
        }
        pressedAt = nil
        releasedPress = nil
        let date = Date()
        initialPose = motionStartedAt.map {
            AtlasPipMotion.pose(at: date.timeIntervalSince($0), intensity: reaction.intensity, from: initialPose)
        } ?? .rest
        motionStartedAt = reduceMotion ? nil : date
        // Blink after the arm arrives, rather than at the instant of contact.
        idleStartedAt = date.addingTimeInterval(-4.25)
        reaction.activate(at: now, pressDuration: duration)
        reactionSequence += 1
    }

    private func stopGreeting() {
        pressedAt = nil
        releasedPress = nil
        motionStartedAt = nil
        initialPose = .rest
        reaction.settle()
        reactionSequence += 1
    }
}

private struct PipRig: View {
    let pose: AtlasPipPose
    let eyeOpenness: Double

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 513
            ZStack {
                part("PipLeftFoot")
                    .rotationEffect(.degrees(pose.leftFootAngle), anchor: UnitPoint(x: 183.0 / 513, y: 448.0 / 513))
                part("PipRightFoot")
                    .rotationEffect(.degrees(pose.rightFootAngle), anchor: UnitPoint(x: 384.0 / 513, y: 448.0 / 513))
                ZStack {
                    part("PipArm")
                        .rotationEffect(.degrees(pose.armAngle), anchor: UnitPoint(x: 423.0 / 513, y: 349.0 / 513))
                    part("PipBody")
                    part("PipEyes")
                        .scaleEffect(x: 1, y: eyeOpenness, anchor: UnitPoint(x: 0.5, y: 246.0 / 513))
                    PipClosedEyes()
                        .stroke(Color(red: 0.035, green: 0.02, blue: 0.07), style: StrokeStyle(lineWidth: 7 * unit, lineCap: .round))
                        .opacity(max(0, 1 - eyeOpenness * 4))
                }
                .rotationEffect(.degrees(pose.bodyAngle), anchor: UnitPoint(x: 285.0 / 513, y: 373.0 / 513))
                .offset(y: pose.bodyDrop * unit)
            }
        }
    }

    private func part(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
    }
}

private struct PipClosedEyes: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 513
        var path = Path()
        for x in [210.0, 322.0] {
            path.move(to: CGPoint(x: x * unit, y: 248 * unit))
            path.addQuadCurve(
                to: CGPoint(x: (x + 47) * unit, y: 248 * unit),
                control: CGPoint(x: (x + 23.5) * unit, y: 227 * unit)
            )
        }
        return path
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
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 160, height: dynamicTypeSize.isAccessibilitySize ? 96 : 160)

            VStack(spacing: 8) {
                Text("Meet Pip")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Your Atlas companion. Ask a question or work out your next step.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
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

struct AtlasThreadActivity: View {
    let message: String
    let typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || scenePhase != .active)) { context in
            let phase = reduceMotion || scenePhase != .active ? 0 : context.date.timeIntervalSinceReferenceDate * 4
            HStack(spacing: 12) {
                if typing {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle().fill(.tint).frame(width: 6, height: 6)
                                .opacity(reduceMotion ? 1 : 0.45 + 0.55 * (sin(phase - Double(index)) + 1) / 2)
                                .offset(y: reduceMotion ? 0 : -2 * sin(phase - Double(index)))
                        }
                    }
                    .frame(width: 32, height: 32)
                } else {
                    AtlasPipView(interactive: false)
                    .frame(width: 32, height: 32)
                }
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("thread-agent-activity")
    }
}
