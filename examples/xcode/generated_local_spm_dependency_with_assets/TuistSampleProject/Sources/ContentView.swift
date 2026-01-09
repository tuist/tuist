import SwiftUI
import DependencyWithImages

public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack {
            Text("Hello, World!")
                .padding()
            LogoImage()
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
