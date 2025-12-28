import DataGenerator
import SwiftAndTipsMacros
import SwiftUI

@SampleBuilder(numberOfItems: 3, dataGeneratorType: .random)
struct Product {
    var price: Int
    var description: String
}

@main
struct TuistApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
