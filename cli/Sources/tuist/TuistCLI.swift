import Foundation
import Path

#if os(macOS)
    import FileSystem
    import Noora
    import TSCBasic
    import TuistKit
    import TuistSupport
#endif

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await initDependencies { logFilePath in
            #if os(macOS)
                try await TuistCommand.main(logFilePath: logFilePath)
            #else
                try await TuistCommand.main()
            #endif
        }
    }
}
