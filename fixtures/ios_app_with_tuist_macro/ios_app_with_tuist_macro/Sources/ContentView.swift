import SwiftUI
import TuistMacro

public struct ContentView: View {
	private let result = #stringify(1 + 1)
	
    public var body: some View {
		VStack {
			Text("Hello, \(result)")
		}
		.padding()
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
