import Alamofire
import SwiftUI

struct ContentView: View {
    init() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")
    }

    var body: some View {
        Text("Hello, World!")
            .padding()
    }
}

#Preview {
    ContentView()
}
