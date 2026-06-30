import SwiftUI
import TuistMacro

public struct ContentView: View {
	let result = #stringify(17 + 25)
	
    public var body: some View {
		VStack {
			Text("Hello, \(result.0)!")
		}
		.padding()
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
