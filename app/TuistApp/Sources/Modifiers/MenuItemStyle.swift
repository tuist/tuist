import Foundation
import SwiftUI

private struct MenuItemSyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(MenuItemButtonStyle())
            .padding(.horizontal, 6)
            .hoverStyle()
            .cornerRadius(5.0)
    }
}

extension View {
    func menuItemStyle() -> some View {
        modifier(MenuItemSyle())
    }
}

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
