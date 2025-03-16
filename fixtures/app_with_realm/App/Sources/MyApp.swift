import RealmSwift
import SwiftUI

@main
struct MyApp: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class RealmObject: RealmSwift.Object {}
