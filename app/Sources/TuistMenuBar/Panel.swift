import SwiftUI

struct Panel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .background(.thinMaterial)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(showProminentBorder ? 0.1 : 0), lineWidth: lineWidth)
            )
            .padding(lineWidth)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + lineWidth)
                    .strokeBorder(.black.opacity(showProminentBorder ? 0.2 : 0), lineWidth: lineWidth)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: cornerRadius, x: 0, y: 2)
    }

    private var showProminentBorder: Bool {
        colorScheme == .dark
    }

    private let lineWidth: CGFloat = 0.5
    private let cornerRadius: CGFloat = 8
}
