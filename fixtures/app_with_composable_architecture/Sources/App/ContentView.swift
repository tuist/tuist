import SwiftUI
import A
import B
import ComposableArchitecture

public struct ContentView: View {
    let storeA: StoreOf<FeatureAReducer>
    let storeB: StoreOf<FeatureBReducer>

    public var body: some View {
        Text("Hello, World!")
            .padding()
    }
}
