import SwiftUI

/// A gently swaying droplet beside the agent's current work, not a progress estimate.
struct WorkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let phase = reduceMotion || scenePhase != .active ? 0 : context.date.timeIntervalSinceReferenceDate * .pi / 1.2
            let sway = sin(phase)
            let squash = 1 - cos(phase * 2)
            ZStack {
                WorkingDrop(lean: sway)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.27, blue: 1),
                                                  Color(red: 0.43, green: 0.23, blue: 0.80)],
                                         startPoint: .top, endPoint: .bottom))
                HStack(spacing: 3.5) {
                    ForEach(0..<2) { _ in
                        Capsule().fill(Color(red: 0.09, green: 0.05, blue: 0.15))
                            .frame(width: 3, height: 7)
                    }
                }
                .offset(x: sway * 1.5, y: 3)
            }
            .frame(width: 24, height: 28)
            .scaleEffect(x: 1 + squash * 0.035, y: 1 - squash * 0.025, anchor: .bottom)
            .rotationEffect(.degrees(sway * 22), anchor: UnitPoint(x: 0.5, y: 0.7))
            .frame(width: 32, height: 32)
        }
        .accessibilityHidden(true)
    }
}

private struct WorkingDrop: Shape {
    let lean: Double

    func path(in rect: CGRect) -> Path {
        let tip = 0.5 + lean * 0.09
        var path = Path()
        path.move(to: CGPoint(x: rect.width * (tip - 0.1), y: rect.height * 0.08))
        path.addQuadCurve(to: CGPoint(x: rect.width * (tip + 0.1), y: rect.height * 0.08),
                          control: CGPoint(x: rect.width * tip, y: -rect.height * 0.06))
        path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.59),
                      control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.27),
                      control2: CGPoint(x: rect.width, y: rect.height * 0.41))
        path.addCurve(to: CGPoint(x: 0, y: rect.height * 0.59),
                      control1: CGPoint(x: rect.width, y: rect.height * 1.14),
                      control2: CGPoint(x: 0, y: rect.height * 1.14))
        path.addCurve(to: CGPoint(x: rect.width * (tip - 0.1), y: rect.height * 0.08),
                      control1: CGPoint(x: 0, y: rect.height * 0.41),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.27))
        path.closeSubpath()
        return path
    }
}
