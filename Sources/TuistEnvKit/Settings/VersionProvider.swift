import Combine
import CombineExt
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

protocol VersionProviding {
    /// Returns the list of versions available on GitHub by parsing the CHANGELOG.md file
    /// - Returns: A publisher to obtain the versions.
    func versions() -> AnyPublisher<[Version], Error>

    /// Returns the latest available version
    /// - Returns: A publisher to obtain the latest available version.
    func latestVersion() -> AnyPublisher<Version, Error>
}

enum VersionProviderError: FatalError {
    case noVersionsError

    var description: String {
        switch self {
        case .noVersionsError:
            return "Error fetching versions from GitHub."
        }
    }

    var type: ErrorType {
        switch self {
        case .noVersionsError: return .bug
        }
    }
}

class VersionProvider: VersionProviding {
    let gitHandler: GitHandling

    init(gitHandler: GitHandling = GitHandler()) {
        self.gitHandler = gitHandler
    }

    func versions() -> AnyPublisher<[Version], Error> {
        do {
            let content = try gitHandler.lsremote(url: Constants.gitRepositoryURL, tagsOnly: true, sort: "v:refname")
            let versions = try parseVersionsFromGit(content)
            return AnyPublisher(value: versions)
        } catch {
            return AnyPublisher(error: error)
        }
    }

    func latestVersion() -> AnyPublisher<Version, Error> {
        versions().tryMap { versions -> Version in
            guard let version = versions.last else {
                throw VersionProviderError.noVersionsError
            }
            return version
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Fileprivate

    fileprivate func parseVersionsFromGit(_ gitOutput: String) throws -> [Version] {
        let regex = try NSRegularExpression(pattern: ##"tags/([0-9]+.[0-9]+.[0-9]+)"##, options: [])
        let changelogRange = NSRange(
            gitOutput.startIndex ..< gitOutput.endIndex,
            in: gitOutput
        )
        let matches = regex.matches(in: gitOutput, options: [], range: changelogRange)

        let versions = matches.map { result -> Version in
            let matchRange = result.range(at: 1)
            return Version(stringLiteral: String(gitOutput[Range(matchRange, in: gitOutput)!]))
        }
        return versions
    }
}
