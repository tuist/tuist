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

    /// Tag discovery goes through git rather than a provider API.
    ///
    /// The provider APIs bought nothing here: `git ls-remote --tags` returns every tag with
    /// its peeled annotation in one round trip, whereas GitHub's and GitLab's tag endpoints
    /// page at 100 entries, so on a package with many tags the API path is the slower one.
    /// What they cost is a second credential system — an API request authenticates only with
    /// the ambient provider token, so on a machine whose working credential is a `~/.netrc`
    /// entry or a credential helper it is a guaranteed-404 request per package before git
    /// runs anyway. Delegating leaves one ladder instead of two.
    private static func fetchRemoteVersions(location: String) async throws -> [RemoteVersion] {
        (try? await gitRemoteVersions(location: location)) ?? []
    }

    private static func gitRemoteVersions(location: String) async throws -> [RemoteVersion] {
        var attempts: [(attempt: GitFetchAttempt, error: any Error)] = []
        for attempt in await SourceControlLocations.fetchAttempts(location) {
            do {
                let output = try await SystemProcess.output(
                    "/usr/bin/git",
                    attempt.configArguments + ["ls-remote", "--tags", attempt.location],
                    environment: SystemProcess.nonInteractiveGitEnvironment
                )
                await ResolvedPackageCredentials.shared.record(attempt.credential, for: location)
                return parseGitRemoteVersions(output)
            } catch {
                attempts.append((attempt, error))
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

    static func resolveNamedRef(location: String, name: String) async throws -> String {
        var attempts: [(attempt: GitFetchAttempt, error: any Error)] = []
        for attempt in await SourceControlLocations.fetchAttempts(location) {
            do {
                let output = try await SystemProcess.output(
                    "/usr/bin/git",
                    attempt.configArguments + ["ls-remote", attempt.location, name],
                    environment: SystemProcess.nonInteractiveGitEnvironment
                )
                guard let line = output.split(separator: "\n").first,
                      let revision = line.split(whereSeparator: \.isWhitespace).first
                else {
                    throw ToolError.message("\(name) was not found in \(attempt.location)")
                }
                await ResolvedPackageCredentials.shared.record(attempt.credential, for: location)
                return String(revision)
            } catch {
                attempts.append((attempt, error))
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
