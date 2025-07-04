import SwiftUI

public struct NooraButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void
    @State private var rotation: Double = 0
    @State private var timer: Timer?

    public init(
        title: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(Noora.Colors.buttonEnabledLabel)
                .opacity(isLoading ? 0 : 1)
                .padding(.horizontal, Noora.Spacing.spacing5)
                .padding(.vertical, Noora.Spacing.spacing2)
                .overlay(
                    RoundedRectangle(cornerRadius: Noora.CornerRadius.max)
                        .trim(from: isLoading ? 0.2 : 0, to: isLoading ? 0.9 : 1)
                        .fill(Noora.Colors.buttonEnabledBackground.opacity(isLoading ? 0.0 : 1.0))
                        .stroke(
                            Noora.Colors.buttonEnabledBackground.opacity(isLoading ? 1.0 : 0.0),
                            lineWidth: 2
                        )
                        .rotationEffect(.degrees(rotation))
                        .frame(width: isLoading ? 24 : nil, height: isLoading ? 24 : nil)
                )
                .animation(.easeInOut(duration: 0.1), value: isLoading)
                .onChange(of: isLoading) { _, newValue in
                    if newValue {
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                    } else {
                        timer?.invalidate()
                        withAnimation(.linear(duration: 0)) {
                            rotation = 0
                        }
                    }
                }
        }
    }
}

#Preview("NooraButton") {
    VStack(spacing: 16) {
        NooraButton(title: "Run") {
            print("Run button tapped")
        }

        NooraButton(title: "Run", isLoading: true) {
            print("Loading button tapped")
        }
    }
    .padding()
}
