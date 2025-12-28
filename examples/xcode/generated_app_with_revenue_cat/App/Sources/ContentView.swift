import RevenueCat
import SwiftUI

public struct ContentView: View {
    public init() {
        // Use RevenueCat
        _ = RevenueCat.SubscriptionPeriod(value: 0, unit: .day)
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
