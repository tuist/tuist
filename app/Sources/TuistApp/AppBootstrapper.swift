import TuistLogging

@MainActor
enum AppBootstrapper {
    static func bootstrap() {
        ApplicationLogStore.current.bootstrap()
    }
}
