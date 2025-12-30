import Spine
import SwiftUI

public struct ContentView: View {
    let spineController = SpineController()

    public init() {}

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
