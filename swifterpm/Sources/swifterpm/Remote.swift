import Foundation

struct RemoteVersion: Codable {
    let version: String
    let revision: String

    var semver: SemVer? {
        try? SemVer(version)
    }
}

private struct RemoteVersionsCache: Codable {
    let location: String
    let versions: [RemoteVersion]
}

enum RemoteMetadata {
    static func versions(location: String, cache: Cache) async throws -> [RemoteVersion] {
        if let cached = try await readCachedRemoteVersions(cache: cache, location: location) {
            return cached
        }
        let lock = try await cache.lock(namespace: "remote-versions", key: location)
        _ = lock
        if let cached = try await readCachedRemoteVersions(cache: cache, location: location) {
            return cached
        }
        let versions = try await fetchRemoteVersions(location: location)
        try await writeCachedRemoteVersions(cache: cache, location: location, versions: versions)
        return versions
    }

    private static func fetchRemoteVersions(location: String) async throws -> [RemoteVersion] {
        let repo = try? GitHubRepo(location: location)
        if let repo, await GitHubAuth.hasSession() {
            let apiVersions = (try? await githubRemoteVersions(repo: repo)) ?? []
            if !apiVersions.isEmpty {
                return apiVersions
            }
        }

        let gitLabRepo = try? GitLabRepo(location: location)
        if let gitLabRepo, await GitLabAuth.hasSession(host: gitLabRepo.host) {
            let apiVersions = (try? await GitLabAPI.remoteVersions(repo: gitLabRepo)) ?? []
            if !apiVersions.isEmpty {
                return apiVersions
            }
        }

        let gitVersions = (try? await gitRemoteVersions(location: location)) ?? []
        if !gitVersions.isEmpty {
            return gitVersions
        }
        return []
    }

    private static func gitRemoteVersions(location: String) async throws -> [RemoteVersion] {
        var attempts: [(candidate: String, error: any Error)] = []
        for candidate in SourceControlLocations.fetchCandidates(location) {
            do {
                let authArguments = await GitTransportAuth.configArguments(for: candidate)
                let output = try await SystemProcess.output(
                    "/usr/bin/git", authArguments + ["ls-remote", "--tags", candidate],
                    environment: SystemProcess.nonInteractiveGitEnvironment
                )
                return parseGitRemoteVersions(output)
            } catch {
                attempts.append((candidate, error))
            }
        }
        throw GitFetchFailure.error(location: location, attempts: attempts)
    }

    private static func parseGitRemoteVersions(_ output: String) -> [RemoteVersion] {
        var peeled: [String: String] = [:]
        var direct: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            let sha = String(parts[0])
            let refName = String(parts[1])
            guard refName.hasPrefix("refs/tags/") else { continue }
            var tag = String(refName.dropFirst("refs/tags/".count))
            if tag.hasSuffix("^{}") {
                tag = String(tag.dropLast(3))
                peeled[tag] = sha
            } else {
                direct[tag] = sha
            }
        }

        var versions: [RemoteVersion] = []
        for (tag, sha) in direct {
            guard let version = RemoteMetadata.parseSwiftTagVersion(tag) else { continue }
            versions.append(
                RemoteVersion(version: version.description, revision: peeled[tag] ?? sha)
            )
        }
        return versions.sorted {
            SemVer.ascendingForSort(
                (try? SemVer($0.version)) ?? SemVer(major: 0, minor: 0, patch: 0),
                (try? SemVer($1.version)) ?? SemVer(major: 0, minor: 0, patch: 0)
            )
        }
    }

    private static func githubRemoteVersions(repo: GitHubRepo) async throws -> [RemoteVersion] {
        struct TagsResponse: Decodable {
            struct Commit: Decodable { let sha: String }
            let name: String
            let commit: Commit
        }

        var versions: [RemoteVersion] = []
        var page = 1
        while true {
            let url = URL(
                string:
                "https://api.github.com/repos/\(repo.owner)/\(repo.repo)/tags?per_page=100&page=\(page)"
            )!
            var headers = ["User-Agent": "swifterpm/0.1"]
            if let token = await GitHubAuth.token() {
                headers["Authorization"] = "Bearer \(token)"
            }
            let tags = try JSONDecoder().decode(
                [TagsResponse].self, from: try await HTTPClient.data(url: url, headers: headers)
            )
            if tags.isEmpty {
                break
            }
            for tag in tags {
                if let version = RemoteMetadata.parseSwiftTagVersion(tag.name) {
                    versions.append(
                        RemoteVersion(version: version.description, revision: tag.commit.sha)
                    )
                }
            }
            page += 1
        }
        return versions.sorted {
            SemVer.ascendingForSort(
                (try? SemVer($0.version)) ?? SemVer(major: 0, minor: 0, patch: 0),
                (try? SemVer($1.version)) ?? SemVer(major: 0, minor: 0, patch: 0)
            )
        }
    }

    static func resolveNamedRef(location: String, name: String) async throws -> String {
        var attempts: [(candidate: String, error: any Error)] = []
        for candidate in SourceControlLocations.fetchCandidates(location) {
            do {
                let authArguments = await GitTransportAuth.configArguments(for: candidate)
                let output = try await SystemProcess.output(
                    "/usr/bin/git", authArguments + ["ls-remote", candidate, name],
                    environment: SystemProcess.nonInteractiveGitEnvironment
                )
                guard let line = output.split(separator: "\n").first,
                      let revision = line.split(whereSeparator: \.isWhitespace).first
                else {
                    throw ToolError.message("\(name) was not found in \(candidate)")
                }
                return String(revision)
            } catch {
                attempts.append((candidate, error))
            }
        }
        throw GitFetchFailure.error(location: location, attempts: attempts)
    }

    static func parseSwiftTagVersion(_ tag: String) -> SemVer? {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return try? SemVer(value)
    }

    private static func readCachedRemoteVersions(cache: Cache, location: String) async throws
        -> [RemoteVersion]?
    {
        let path = cache.remoteVersionsPath(location: location)
        guard try await fileSystem.exists(path.absolutePath) else { return nil }
        if let modified = try await fileSystem.fileMetadata(at: path.absolutePath)?.lastModificationDate,
           Date().timeIntervalSince(modified) > 60 * 60
        {
            return nil
        }
        let cached = try JSONDecoder().decode(
            RemoteVersionsCache.self, from: try await fileSystem.readFile(at: path.absolutePath)
        )
        guard cached.location == location else { return nil }
        return cached.versions
    }

    private static func writeCachedRemoteVersions(
        cache: Cache, location: String, versions: [RemoteVersion]
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data =
            try encoder.encode(RemoteVersionsCache(location: location, versions: versions))
                + Data("\n".utf8)
        try await fileSystem.atomicWrite(
            data, to: cache.remoteVersionsPath(location: location)
        )
    }
}
