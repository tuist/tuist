import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

protocol PackageLinting: AnyObject {
    func lint(_ package: Package) -> [LintingIssue]
}

class PackageLinter: PackageLinting {
    private let fileHandler: FileHandling

    init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    func lint(_ package: Package) -> [LintingIssue] {
        if case let .local(path) = package, !fileHandler.exists(path) {
            let issue = LintingIssue(
                reason: "Package with local path (\(path)) does not exist.",
                severity: .error
            )
            return [issue]
        } else if case let .remote(url, _) = package, URL(string: url) == nil {
            let issue = LintingIssue(
                reason: "Package with remote URL (\(url)) does not have a valid URL.",
                severity: .error
            )
            return [issue]
        } else {
            return []
        }
    }
}
