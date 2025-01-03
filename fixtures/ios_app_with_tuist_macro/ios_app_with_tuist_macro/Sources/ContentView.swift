import SwiftUI
import TuistMacro

public struct ContentView: View {
    public var body: some View {
		VStack {
			Text("Hello, World!")
			Text(#stringify(1 + 1 ))
		}
		.padding()
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
