import SwiftUI

struct AtlasPeopleView: View {
    @ObservedObject var presence: AtlasPresence

    var body: some View {
        List {
            Section {
                ForEach(presence.people) { person in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.title)
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(person.name).font(.headline)
                            Text(person.email).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(person.online ? "Online" : "Offline", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(person.online ? Color.green : Color.secondary)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Availability updates while Atlas is active. It does not mean someone is editing.")
            }
            if let message = presence.errorMessage {
                Section { Text(message).foregroundStyle(.secondary) }
            } else if presence.people.isEmpty {
                ProgressView("Loading people")
            }
        }
        .modifier(AtlasThemedContent())
        .navigationTitle("People")
        .toolbar {
            AtlasPresenceToolbar()
            ToolbarItem(placement: .topBarTrailing) { AtlasBrowserButton(screen: "people") }
        }
        .onAppear { presence.show(resource: "people") }
    }
}

struct AtlasPresenceToolbar: ToolbarContent {
    @Environment(\.atlasPresence) private var presence

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let presence { AtlasAlsoHere(presence: presence) }
        }
    }
}

private struct AtlasAlsoHere: View {
    @ObservedObject var presence: AtlasPresence

    var body: some View {
        let people = presence.people.filter(\.here)
        if !people.isEmpty {
            Menu {
                Section("Also here") {
                    ForEach(people) { person in Text(person.name) }
                }
            } label: {
                Label("\(people.count)", systemImage: "person.2.fill")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Also here")
            .accessibilityValue(people.map(\.name).joined(separator: ", "))
            .accessibilityIdentifier("also-here")
        }
    }
}
