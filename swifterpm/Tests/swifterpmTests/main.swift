import FileSystem
import Foundation
import Testing
@testable import SwifterPMCore

if let temporaryDirectory = ProcessInfo.processInfo.environment["TEST_TMPDIR"] {
    let home = URL(fileURLWithPath: temporaryDirectory).appendingPathComponent("home")
    let cache = home.appendingPathComponent("cache")
    try await fileSystem.makeDirectory(at: cache.absolutePath, options: [.createTargetParentDirectories])
    guard setenv("HOME", home.path, 1) == 0, setenv("XDG_CACHE_HOME", cache.path, 1) == 0 else {
        throw ToolError.message("could not configure the test-private home and cache directories")
    }
}

let exitCode: CInt = await Testing.__swiftPMEntryPoint()
Foundation.exit(exitCode)
