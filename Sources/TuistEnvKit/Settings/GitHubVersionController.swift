import Combine
import CombineExt
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

protocol GitHubVersionControlling {
    /// Returns the list of versions available on GitHub by parsing the CHANGELOG.md file
    /// - Returns: A publisher to obtain the versions.
    func versions() -> AnyPublisher<[Version], Error>

    /// Returns the latest available version by parsing the Constants.swift file.
    /// - Returns: A publisher to obtain the latest available version.
    func latestVersion() -> AnyPublisher<Version, Error>
}

enum GitHubVersionControllerError: FatalError {
    case dataDecodingError(url: Foundation.URL)
    case responseError(url: Foundation.URL, content: String, statusCode: Int)
    case versionNotFoundInConstants

    var description: String {
        switch self {
        case let .dataDecodingError(url):
            return "Error decoding the response from \(url.absoluteString) as an utf8 string."
        case let .responseError(url, content, statusCode):
            return """
            The request to \(url.absoluteString) return an unsuccessful response with status code \(statusCode) and error body:
            \(content)
            """
        case .versionNotFoundInConstants:
            return "We couldn't obtain the latest Tuist version from the Constants.swift file."
        }
    }

    var type: ErrorType {
        switch self {
        case .dataDecodingError: return .bug
        case .responseError: return .bug
        case .versionNotFoundInConstants: return .bug
        }
    }
}

class GitHubVersionController: GitHubVersionControlling {
    let requestDispatcher: HTTPRequestDispatching

    init(requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher()) {
        self.requestDispatcher = requestDispatcher
    }

    func versions() -> AnyPublisher<[Version], Error> {
        return requestDispatcher.dispatch(resource: changelogResource())
            .flatMapLatest { (content, _) -> AnyPublisher<[Version], Error> in
                do {
                    let versions = try self.parseVersionsFromChangelog(content)
                    return AnyPublisher(value: versions)
                } catch {
                    return AnyPublisher(error: error)
                }
            }
            .eraseToAnyPublisher()
    }

    func latestVersion() -> AnyPublisher<Version, Error> {
        return requestDispatcher.dispatch(resource: constantsResource())
            .flatMapLatest { (content, _) -> AnyPublisher<Version, Error> in
                do {
                    return AnyPublisher(value: try self.parseLatestVersionFromConstants(content))
                } catch {
                    return AnyPublisher(error: error)
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Fileprivate

    fileprivate func parseVersionsFromChangelog(_ changelog: String) throws -> [Version] {
        let regex = try NSRegularExpression(pattern: "##\\s+([0-9]+.[0-9]+.[0-9]+)", options: [])
        let changelogRange = NSRange(
            changelog.startIndex ..< changelog.endIndex,
            in: changelog
        )
        let matches = regex.matches(in: changelog, options: [], range: changelogRange)

        let versions = matches.map { result -> Version in
            let matchRange = result.range(at: 1)
            return Version(stringLiteral: String(changelog[Range(matchRange, in: changelog)!]))
        }
        return versions
    }

    fileprivate func parseLatestVersionFromConstants(_ constants: String) throws -> Version {
        let regex = try NSRegularExpression(pattern: "static\\slet\\sversion\\s=\\s\"([0-9]+\\.[0-9]+\\.[0-9]+)\"", options: [])
        let constantsRange = NSRange(
            constants.startIndex ..< constants.endIndex,
            in: constants
        )

        guard let match = regex.firstMatch(in: constants, options: [], range: constantsRange) else {
            throw GitHubVersionControllerError.versionNotFoundInConstants
        }
        let matchRange = match.range(at: 1)
        return Version(stringLiteral: String(constants[Range(matchRange, in: constants)!]))
    }

    fileprivate func constantsResource() -> HTTPResource<String, Error> {
        return resource(path: "/Sources/TuistSupport/Constants.swift")
    }

    fileprivate func changelogResource() -> HTTPResource<String, Error> {
        return resource(path: "/CHANGELOG.md")
    }

    fileprivate func resource(path: String) -> HTTPResource<String, Error> {
        return HTTPResource {
            var request = URLRequest(url: self.rawFileURL(path: path))
            request.httpMethod = "GET"
            return request
        } parse: { data, response in
            guard let content = String(data: data, encoding: .utf8) else {
                throw GitHubVersionControllerError.dataDecodingError(url: response.url!)
            }
            return content
        } parseError: { errorData, response in
            let content = String(data: errorData, encoding: .utf8) ?? ""
            return GitHubVersionControllerError.responseError(
                url: response.url!,
                content: content,
                statusCode: response.statusCode
            )
        }
    }

    fileprivate func rawFileURL(path: String) -> Foundation.URL {
        return URL(string: "https://raw.githubusercontent.com/tuist/tuist/main\(path)")!
    }
}
