import FileSystem
import Foundation
import Noora
import Path
import ServiceContextModule
import TSCBasic
import TuistKit
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await ServiceContext.tuist { logFilePath in
            try await TuistCommand.main(logFilePath: logFilePath)
        }
    }
}
