import Alamofire
import SwiftUI

public struct ContentView: View {
    public init() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://tuist.dev")
    }

    public var body: some View {
        Text("Hello, World!")
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
