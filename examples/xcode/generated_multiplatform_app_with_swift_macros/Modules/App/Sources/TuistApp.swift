import SwiftUI
#if os(iOS)
    import iOSStaticFramework
#endif

#if os(watchOS)
    import WatchOSDynamicFramework
#endif

#if os(macOS)
    import MacOSStaticFramework
#endif

@main
struct TuistApp: App {
    #if os(iOS)
        let iosStaticFramework = iOSStaticFrameworkClass()
    #endif
    #if os(watchOS)
        let watchOSDynamicFramework = WatchOSDynamicFrameworkClass()
    #endif
    #if os(macOS)
        let macOSStaticFramework = MacOSStaticFrameworkClass()
    #endif

    var body: some Scene {
        WindowGroup {
            Text("Tuist is great")
            #if os(iOS)
                if #available(iOS 15.0, *) {
                    AsyncImage(url: iosStaticFramework.logoURL)
                } else {
                    // Fallback on earlier versions
                }
            #endif
        }
    }
}
