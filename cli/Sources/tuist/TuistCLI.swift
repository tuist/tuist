import Foundation

#if os(macOS)
    import FileSystem
    import Noora
    import Path
    import TSCBasic
    import TuistKit
    import TuistSupport
#endif

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        #if os(macOS)
            try await initDependencies { logFilePath in
                try await TuistCommand.main(logFilePath: logFilePath)
            }
        #else
            try await initDependencies {
                try await TuistCommand.main()
            }
        #endif
    }
}
