import Foundation
import SwiftUI

private struct MenuItemSyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
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
