import SwiftUI

/// Liquid Glass where the OS has it (iOS and macOS 26), and the closest
/// earlier system style otherwise, so the app keeps its iOS 17 and macOS 14 floor.
extension View {
    @ViewBuilder func glassButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder func prominentGlassButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder func glass(in shape: some Shape) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.bar, in: shape)
        }
    }

    @ViewBuilder func interactiveGlass(in shape: some Shape) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.bar, in: shape)
        }
    }
}
