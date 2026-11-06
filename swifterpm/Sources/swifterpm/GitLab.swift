import Foundation

struct GitLabRepo {
    let scheme: String
    let host: String
    let pathWithNamespace: String

    init(location: String) throws {
        let normalized = Self.normalize(location)
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased()
        else {
            throw ToolError.message("not a GitLab URL")
        }

        let path = url.path
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "/")
        guard Self.isKnownHost(host),
              path.split(separator: "/").count >= 2
        else {
            throw ToolError.message("not a GitLab URL")
        }

        scheme = url.scheme ?? "https"
        self.host = host
        pathWithNamespace = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
    }

    var apiBaseURL: URL {
        let env = Environment.current
        let apiHost = env["GITLAB_API_HOST"]?.gitLabNormalizedHost ?? host
        let apiScheme =
            env["GITLAB_URI"].flatMap(URL.init(string:))?.scheme
                ?? env["GITLAB_HOST"].flatMap(URL.init(string:))?.scheme
                ?? scheme
        return URL(string: "\(apiScheme)://\(apiHost)/api/v4")!
    }

    var encodedProjectPath: String {
        GitLabURLCoding.encodePathComponent(pathWithNamespace)
    }

    private static func normalize(_ location: String) -> String {
        if location.hasPrefix("git@") {
            let value = String(location.dropFirst("git@".count))
            guard let separator = value.firstIndex(of: ":") else {
                return location
            }
            let host = value[..<separator]
            let path = value[value.index(after: separator)...]
            return "https://\(host)/\(path)"
        }
        if location.hasPrefix("ssh://git@") {
            return
                location
                    .replacingOccurrences(of: "ssh://git@", with: "https://")
        }
        return location
    }

    static func isKnownHost(_ host: String) -> Bool {
        if host == "gitlab.com" || host.contains("gitlab") {
            return true
        }
        return configuredHosts.contains(host)
    }

    static var configuredHosts: [String] {
        let environment = Environment.current
        return ["SWIFTERPM_GITLAB_HOST", "GITLAB_HOST", "GITLAB_URI", "GITLAB_API_HOST", "CI_SERVER_HOST", "CI_SERVER_FQDN"]
            .compactMap { environment[$0]?.gitLabNormalizedHost }
    }
}

extension String {
    fileprivate var gitLabNormalizedHost: String? {
        let location = contains("://") ? self : "https://\(self)"
        return URL(string: location)?.host?.lowercased()
    }
}

private enum GitLabURLCoding {
    static func encodePathComponent(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum GitLabAuth {
    enum Token {
        case privateToken(String)
        case jobToken(String)
        case bearer(String)

        var header: [String: String] {
            switch self {
            case let .privateToken(token):
                return ["PRIVATE-TOKEN": token]
            case let .jobToken(token):
                return ["JOB-TOKEN": token]
            case let .bearer(token):
                return ["Authorization": "Bearer \(token)"]
            }
        }

    }

    static func token(for apiURL: URL) async -> Token? {
        guard apiURL.scheme == "https", let host = apiURL.host?.lowercased(),
              host == "gitlab.com" || GitLabRepo.configuredHosts.contains(host)
        else { return nil }
        guard let token = Environment.current["SWIFTERPM_GITLAB_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
        else { return nil }
        return .privateToken(token)
    }

    static func hasSession(for repo: GitLabRepo) async -> Bool {
        await token(for: repo.apiBaseURL) != nil
    }
}

enum GitLabAPI {
    static func remoteVersions(repo: GitLabRepo) async throws -> [RemoteVersion] {
        struct TagsResponse: Decodable {
            struct Commit: Decodable { let id: String }
            let name: String
            let commit: Commit
        }

        var versions: [RemoteVersion] = []
        var page = 1
        while true {
            let url = repo.apiBaseURL
                .appendingGitLabProjectAPIPath(repo.encodedProjectPath, ["repository", "tags"])
                .appending(queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ])
            let tags = try JSONDecoder().decode(
                [TagsResponse].self,
                from: try await HTTPClient.data(url: url, headers: try await headers(for: repo))
            )
            if tags.isEmpty {
                break
            }
            for tag in tags {
                if let version = RemoteMetadata.parseSwiftTagVersion(tag.name) {
                    versions.append(
                        RemoteVersion(version: version.description, revision: tag.commit.id)
                    )
                }
            }
            page += 1
        }
        return versions.sorted {
            ($0.semver ?? SemVer(major: 0, minor: 0, patch: 0))
                < ($1.semver ?? SemVer(major: 0, minor: 0, patch: 0))
        }
    }

    static func downloadArchive(repo: GitLabRepo, revision: String, destination: URL) async throws {
        let url = repo.apiBaseURL
            .appendingGitLabProjectAPIPath(
                repo.encodedProjectPath, ["repository", "archive.tar.gz"]
            )
            .appending(queryItems: [
                URLQueryItem(name: "sha", value: revision),
            ])
        try await HTTPClient.download(
            url: url, destination: destination, headers: try await headers(for: repo)
        )
    }

    private static func headers(for repo: GitLabRepo) async throws -> [String: String] {
        guard let token = await GitLabAuth.token(for: repo.apiBaseURL) else {
            throw ToolError.message("no GitLab token available for \(repo.host)")
        }
        return token.header.merging(["User-Agent": "swifterpm/0.1"]) { current, _ in current }
    }
}

extension URL {
    fileprivate func appendingGitLabProjectAPIPath(_ projectPath: String, _ components: [String])
        -> URL
    {
        URL(
            string: ([absoluteString, "projects", projectPath] + components).joined(separator: "/")
        )!
    }

    fileprivate func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}
