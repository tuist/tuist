import SwiftUI

struct AtlasAppearanceView: View {
    @EnvironmentObject private var appearance: AtlasAppearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.atlasTheme) private var theme

    var body: some View {
        Form {
            Section("Theme") {
                choice(id: "server-default", title: "Server default", subtitle: "Chosen by your company",
                       theme: appearance.catalog?.themes.first { $0.id == appearance.catalog?.defaultThemeId })
                ForEach(appearance.catalog?.themes ?? []) { theme in
                    choice(id: theme.id, title: theme.name, subtitle: theme.description, theme: theme)
                }
            }
            Section {
                Picker("Appearance", selection: Binding(get: { appearance.mode }, set: { appearance.choose(mode: $0) })) {
                    ForEach(AtlasAppearance.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance-mode")
            } header: {
                Text("Appearance")
            } footer: {
                Text("Saved on this device for this server. Unavailable themes use the server default or original Atlas appearance.")
            }
            if let theme {
                Section("Preview") {
                    preview(theme)
                        .accessibilityIdentifier("appearance-preview")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle("Appearance")
        .modifier(AtlasThemedContent())
        .task { await appearance.refresh() }
    }

    private func choice(id: String, title: String, subtitle: String, theme: AtlasTheme?) -> some View {
        Button { appearance.choose(theme: id) } label: {
            HStack(spacing: 12) {
                if let palette = theme?.palette(scheme) {
                    HStack(spacing: -4) {
                        let swatches = [palette.accent, palette.surface, palette.text]
                        ForEach(swatches.indices, id: \.self) { index in
                            Circle().fill(Color(atlasHex: swatches[index])).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
                        }
                    }.accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if appearance.activeSelection == id {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(appearance.activeSelection == id ? .isSelected : [])
        .accessibilityValue(appearance.activeSelection == id ? "Selected" : "")
        .accessibilityIdentifier("theme-\(id)")
    }

    private func preview(_ theme: AtlasTheme) -> some View {
        let palette = theme.palette(scheme)
        return VStack(alignment: .leading, spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review the launch plan")
                        .font(.headline.weight(theme.typography == "strong" ? .bold : .regular))
                    Text("Today").font(.subheadline).foregroundStyle(Color(atlasHex: palette.secondaryText))
                }
            } icon: {
                Image(systemName: "square").foregroundStyle(Color(atlasHex: palette.tint))
            }
            Text("Add task").font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Color(atlasHex: palette.onAccent))
                .background(Color(atlasHex: palette.accent), in: RoundedRectangle(cornerRadius: theme.buttonRadius))
        }
        .fontDesign(theme.typography == "rounded" ? .rounded : .default)
        .padding(16)
        .foregroundStyle(Color(atlasHex: palette.text))
        .background(Color(atlasHex: palette.surface), in: RoundedRectangle(cornerRadius: theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cardRadius).stroke(Color(atlasHex: palette.border), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview: task card and primary action")
    }
}
