import Foundation
import SwiftUI

private struct MenuItemSyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(MenuItemButtonStyle())
            .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .hoverStyle()
            .cornerRadius(5.0)
    }
}

extension View {
    func menuItemStyle() -> some View {
        modifier(MenuItemSyle())
    }
}

struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
