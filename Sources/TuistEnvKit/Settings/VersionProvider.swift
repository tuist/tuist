import Combine
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

protocol VersionProviding {
    /// Returns the list of versions available on GitHub by parsing the release tags.
    /// - Returns: An array of the versions.
    func versions() throws -> [Version]

    /// Returns the latest available version
    /// - Returns: The latest available version, or `nil` if no versions were found.
    func latestVersion() throws -> Version?
}

class VersionProvider: VersionProviding {
    let gitHandler: GitHandling

    init(gitHandler: GitHandling = GitHandler()) {
        self.gitHandler = gitHandler
    }

    func versions() throws -> [Version] {
        try gitHandler.remoteTaggedVersions(url: Constants.gitRepositoryURL)
    }

    func latestVersion() throws -> Version? {
        try versions().last
    }
}
