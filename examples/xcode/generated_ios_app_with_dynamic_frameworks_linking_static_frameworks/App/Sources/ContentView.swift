import DynamicFrameworkA
import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        let choice = Thing().choice
        if choice.is(\.bluePill) {
            Text("Blue")
        } else {
            Text("Red")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
