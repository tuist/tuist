import Foundation

struct GitHubRepo: Sendable {
    let owner: String
    let repo: String

    init(location: String) throws {
        let normalized =
            location.hasPrefix("git@github.com:")
                ? location.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
                : location
        guard let url = URL(string: normalized), url.host == "github.com" else {
            throw ToolError.message("not a GitHub URL")
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw ToolError.message("GitHub URL has no owner or repo")
        }
        owner = parts[0]
        repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
    }
}

private actor GitHubTokenCache {
    private var loaded = false
    private var cachedToken: String?

    func token() async -> String? {
        if loaded {
            return cachedToken
        }
        loaded = true

        let env = ProcessInfo.processInfo.environment
        if let token = env["GITHUB_TOKEN"] ?? env["GH_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            cachedToken = token
            return token
        }

        guard let output = try? await SystemProcess.output("/usr/bin/env", ["gh", "auth", "token"])
        else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedToken = token.isEmpty ? nil : token
        return cachedToken
    }
}

private let githubTokenCache = GitHubTokenCache()

enum GitHubAuth {
    static func token() async -> String? {
        await githubTokenCache.token()
    }

    static func hasSession() async -> Bool {
        await token() != nil
    }
}

enum SourceControlLocations {
    static func canonicalResolvedFileLocation(_ location: String) -> String {
        if let shorthandLocation = ColonSeparatedGitLocation(location) {
            return shorthandLocation.canonicalString
        }
        guard var components = URLComponents(string: location),
              let host = components.host
        else {
            return location
        }

        components.scheme = components.scheme?.lowercased()
        let normalizedHost = host.lowercased()
        components.host = normalizedHost
        if canonicalizesProviderPath(host: normalizedHost) {
            components.path = canonicalProviderPath(components.path)
        }
        return components.string ?? location
    }

    static func fetchCandidates(_ location: String) -> [String] {
        var locations = [location]
        appendGitHubSSHLocation(for: location, to: &locations)
        appendGitLabSSHLocation(for: location, to: &locations)
        return locations
    }

    private static func appendGitHubSSHLocation(for location: String, to locations: inout [String]) {
        guard let repo = try? GitHubRepo(location: location) else { return }
        let ssh = "git@github.com:\(repo.owner)/\(repo.repo).git"
        if !locations.contains(ssh) {
            locations.append(ssh)
        }
    }

    private static func appendGitLabSSHLocation(for location: String, to locations: inout [String]) {
        guard let repo = try? GitLabRepo(location: location) else { return }
        let ssh = "git@\(repo.host):\(repo.pathWithNamespace).git"
        if !locations.contains(ssh) {
            locations.append(ssh)
        }
    }

    fileprivate static func canonicalProviderPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let withoutGit =
            trimmed.lowercased().hasSuffix(".git")
                ? String(trimmed.dropLast(4)) : trimmed
        let path = withoutGit.lowercased()
        return path.isEmpty ? "" : "/\(path)"
    }

    fileprivate static func canonicalizesProviderPath(host: String) -> Bool {
        let host = host.lowercased()
        return host == "github.com" || GitLabRepo.isKnownHost(host)
    }
}

private struct ColonSeparatedGitLocation {
    let user: String
    let host: String
    let path: String

    init?(_ location: String) {
        guard !location.contains("://"),
              let at = location.firstIndex(of: "@"),
              let colon = location[location.index(after: at)...].firstIndex(of: ":")
        else {
            return nil
        }

        let user = String(location[..<at])
        let host = String(location[location.index(after: at) ..< colon])
        let path = String(location[location.index(after: colon)...])
        guard !user.isEmpty, !host.isEmpty, !path.isEmpty else { return nil }

        self.user = user
        self.host = host
        self.path = path
    }

    var canonicalString: String {
        let normalizedHost = host.lowercased()
        let normalizedPath = if SourceControlLocations.canonicalizesProviderPath(host: normalizedHost) {
            SourceControlLocations.canonicalProviderPath(path)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            path
        }
        return "\(user)@\(normalizedHost):\(normalizedPath)"
    }
}
