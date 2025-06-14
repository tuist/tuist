import GCDWebServer
import SBTUITestTunnelServer
import SwiftUI

public struct ContentView: View {
    public init() {
        // Use SBTUITestTunnelServer to make sure it links fine
        _ = SBTUITestTunnelServer()
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
