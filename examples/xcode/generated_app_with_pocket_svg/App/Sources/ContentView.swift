import PocketSVG
import SwiftUI

public struct ContentView: View {
    public init() {
        let svg =
            "<?xml version=\"1.1\" encoding=\"UTF-8\" standalone=\"no\"?> <svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0.000000, 0.000000, 732.000000, 185.000000\" width=\"732.000000\" height=\"185.000000\" > <path fill=\"none\" stroke=\"black\" stroke-width=\"2.000000\" stroke-linejoin=\"round\" stroke-linecap=\"round\" d=\"M148.0 143.0M300.0 143.0\" /> </svg>"
        let generatedPathsFromResponse = SVGBezierPath.paths(fromSVGString: svg)
        assert(!generatedPathsFromResponse.isEmpty)
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
