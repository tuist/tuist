import SwiftUI

@main
struct AtlasApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Text("Your workspace, on the go")
                            .font(.title2.bold())
                        Text("Open a section in your browser. Sign in with your Atlas account to access your workspace.")
                            .foregroundStyle(.secondary)
                    }
                    Section("Workspace") {
                        ForEach(AtlasCore.sections()) { section in
                            Link(destination: section.url) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.headline)
                                    Text(section.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .navigationTitle("Atlas")
                .tint(Color(red: 0.44, green: 0.21, blue: 1))
            }
        }
    }
}
