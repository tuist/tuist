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

    /// A bar of glass controls over a scroll view's bottom edge. On iOS and macOS 26 the content
    /// scrolls under it and fades with the system's scroll edge effect instead of a rule.
    @ViewBuilder func bottomGlassBar(@ViewBuilder _ bar: () -> some View) -> some View {
        if #available(iOS 26, macOS 26, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            safeAreaInset(edge: .bottom, content: bar)
        }
    }

    @ViewBuilder func tintedInteractiveGlass(_ tint: Color, in shape: some Shape) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(tint, in: shape)
        }
    }

    /// The conversation title's glass pill.
    @ViewBuilder func titlePill() -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.bar, in: Capsule())
        }
    }

    /// A conversation opens at its latest message, while a short one stays at the top.
    @ViewBuilder func openingAtLatest() -> some View {
        if #available(iOS 18, macOS 15, *) {
            defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            self
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

extension ToolbarContent {
    /// Drops the glass iOS 26 puts behind a toolbar item, for items that draw their own.
    @ToolbarContentBuilder func sharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26, macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
