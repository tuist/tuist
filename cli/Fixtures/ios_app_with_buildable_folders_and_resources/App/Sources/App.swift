// Created 09/01/2025

import SwiftUI

@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        let jsonExists: Bool = {
            if let url = Bundle.module.url(forResource: "resource", withExtension: "json") {
                return FileManager.default.fileExists(atPath: url.path)
            }
            return false
        }()

        return Text(jsonExists ? "Resource found" : "Resource missing")
            .padding()
    }
}
