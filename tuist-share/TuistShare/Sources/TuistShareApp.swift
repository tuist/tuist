import SwiftUI

@main
struct TuistShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        MenuBarExtra("Tuist Share", systemImage: "iphone") {
            SimulatorView()
                .environmentObject(appDelegate)
//                .onOpenURL { incomingURL in
//                    print("App was opened via URL: \(incomingURL)")
//                }
        }
        .menuBarExtraStyle(.window)
    }
}
