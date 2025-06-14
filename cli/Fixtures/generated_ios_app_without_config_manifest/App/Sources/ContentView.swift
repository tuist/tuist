import SwiftUI
import Yams

struct ContentView: View {
    init() {
        let _ = YAMLDecoder()
    }

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
