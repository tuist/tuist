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
        .navigationTitle("People")
        .onAppear { presence.show(resource: "people") }
    }
}

struct AtlasAlsoHere: View {
    @ObservedObject var presence: AtlasPresence

    var body: some View {
        let names = presence.people.filter(\.here).map(\.name)
        if !names.isEmpty {
            Label("Also here: \(names.joined(separator: ", "))", systemImage: "person.2.fill")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("also-here")
        }
    }
}
