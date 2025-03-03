import LibraryA
import LibraryB
import SwiftUI

public struct ContentView: View {
    public init() {
        LibraryA.libraryA()
        LibraryB.libraryB()
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
