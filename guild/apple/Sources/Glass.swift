import SwiftUI

/// Liquid Glass where the OS has it (iOS and macOS 26), and the closest
/// earlier system style otherwise, so the app keeps its iOS 17 and macOS 14 floor.
extension View {
    @ViewBuilder func prominentGlassButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder func interactiveGlass(in shape: some Shape) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.bar, in: shape)
        }
    }

    #if os(iOS)
        @ViewBuilder func minimizingTabBarOnScroll() -> some View {
            if #available(iOS 26, *) {
                tabBarMinimizeBehavior(.onScrollDown)
            } else {
                self
            }
        }
    #endif
}
