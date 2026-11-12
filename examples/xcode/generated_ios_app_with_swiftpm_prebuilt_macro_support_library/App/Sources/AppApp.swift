import CasePaths
import SwiftUI
import SwiftUINavigation

@CasePathable
enum Destination {
    case detail(String)
    case settings
}

@main
struct AppApp: App {
    @State private var destination: Destination?

    var body: some Scene {
        WindowGroup {
            Button("Show detail") { destination = .detail("Hello") }
                .sheet(item: $destination.detail, id: \.self) { text in
                    Text(text)
                }
        }
    }
}
