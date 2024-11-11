import SwiftUI
import ComposableArchitecture
import A
import B

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                storeA: Store(initialState: FeatureAReducer.State(), reducer: {
                    FeatureAReducer()
                }), storeB: Store(initialState: FeatureBReducer.State(), reducer: {
                    FeatureBReducer()
                })
            )
        }
    }
}
