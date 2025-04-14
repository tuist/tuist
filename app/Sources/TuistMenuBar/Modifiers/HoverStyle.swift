import Foundation
import SwiftUI

private struct HoverStyle: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover(perform: { hovering in
                self.hovering = hovering
            })
            .background(hovering ? .gray.opacity(0.2) : .clear)
    }
}

extension View {
    func hoverStyle() -> some View {
        modifier(HoverStyle())
    }
}
