import LocalSwiftPackage
import SwiftUI

public struct ContentView: View {
    public init() {
        _ = LocalSwiftPackage()
    }

    public var body: some View {
        Text("Hello, World!")
            .padding()
    }
}
