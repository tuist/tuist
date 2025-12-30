import SwiftUI

struct TuistProgressViewStyle<StrokeContent: ShapeStyle>: ProgressViewStyle {
    @State private var isAnimating = false

    private let strokeWidth = 2.0
    private let strokeContent: StrokeContent

    init(strokeContent: StrokeContent = .tertiary) {
        self.strokeContent = strokeContent
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, style: StrokeStyle(lineWidth: strokeWidth))

            if let fractionCompleted = configuration.fractionCompleted {
                Circle()
                    .trim(from: 0, to: fractionCompleted)
                    .stroke(strokeContent, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(-90))

            } else {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(strokeContent, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear {
                        isAnimating = true
                    }
            }

            configuration.label
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 14, height: 14)
        .padding(strokeWidth / 2) // Compensate for middle stroke position
    }
}
