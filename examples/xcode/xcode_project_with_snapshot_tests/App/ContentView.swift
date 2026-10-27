import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
                .font(.title)
            Text("Snapshot Test Example")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
