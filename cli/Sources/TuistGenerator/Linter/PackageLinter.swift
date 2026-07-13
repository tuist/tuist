import FileSystem
import Foundation
import TuistCore
import TuistSupport
import XcodeGraph

protocol PackageLinting {
    func lint(_ package: Package) async throws -> [LintingIssue]
}

struct PackageLinter: PackageLinting {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    func lint(_ package: Package) async throws -> [LintingIssue] {
        if case let .local(path) = package, try await !fileSystem.exists(path) {
            let issue = LintingIssue(
                reason: "Package with local path (\(path)) does not exist.",
                severity: .error
            )
            return [issue]
        } else {
            return []
        }
    }
}
