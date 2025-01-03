import ResourcesFramework
import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text(ResourcesProvider.greeting())
            .padding()
    }
}
