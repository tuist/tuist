import Foundation
import Testing
@testable import SwifterPMCore

struct SupportTests {
    @Test
    func hashingAndRevisionHelpersAreStable() {
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(Hashing.sha256Hex(Data("abc".utf8)) == expected)
        #expect(Hashing.stable("abc") == expected)
        #expect(Hashing.shortRevision("abcdef1234567890") == "abcdef123456")
    }

    @Test
    func atomicWriteCreatesParentDirectories() async throws {
        try await withTemporaryDirectory { root in
            let path = root.appendingPathComponent("nested/file.txt")
            try await fileSystem.atomicWrite("hello", to: path)

            let data = try await fileSystem.readFile(at: path.absolutePath)
            #expect(String(data: data, encoding: .utf8) == "hello")
        }
    }

    @Test
    func systemProcessDrainsStdoutAndStderr() async throws {
        let result = try await SystemProcess.run("/bin/sh", ["-c", "printf out; printf err >&2"])

        #expect(result.stdoutString == "out")
        #expect(result.stderrString == "err")
    }

    @Test
    func binaryArtifactHeadersAskForRawBytesExactly() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/tuist/tuist/releases/assets/1.zip"))
        let headers = await HTTPClient.binaryArtifactHeaders(for: url)

        #expect(headers["Accept"] == "application/octet-stream")
    }

    @Test
    func concurrentTaskMapPreservesInputOrder() async throws {
        let values = [0, 1, 2, 3]
        let mapped = try await ConcurrentTasks.map(values, maxConcurrentTasks: 4) { value in
            try await Task.sleep(nanoseconds: UInt64((values.count - value) * 1_000_000))
            return value
        }

        #expect(mapped == values)
    }

    @Test
    func filesystemHelpersFlattenAndSymlinkDirectory() async throws {
        try await withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source")
            let nested = root.appendingPathComponent("outer/nested")
            try await fileSystem.makeDirectory(at: source.absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.atomicWrite(
                "value", to: source.appendingPathComponent("file.txt")
            )
            try await fileSystem.atomicWrite(
                "nested", to: nested.appendingPathComponent("nested.txt")
            )

            try await fileSystem.flattenSingleDirectory(root.appendingPathComponent("outer"))
            #expect(
                try await fileSystem.exists(root.appendingPathComponent("outer/nested.txt").absolutePath)
            )

            let destination = root.appendingPathComponent("destination")
            try await fileSystem.replaceWithSymlinkedDirectory(
                source: source, destination: destination
            )
            #expect(try await fileSystem.exists(destination.absolutePath))
            #expect(!(fileSystem.isDirectoryAndNotSymlink(destination)))
            #expect(
                try await fileSystem.exists(destination.appendingPathComponent("file.txt").absolutePath)
            )
            let data = try await fileSystem.readFile(at: destination.appendingPathComponent("file.txt").absolutePath)
            #expect(String(data: data, encoding: .utf8) == "value")
            #expect(
                !(fileSystem.isDirectoryAndNotSymlink(
                    destination.appendingPathComponent("file.txt")
                ))
            )
        }
    }

    @Test
    func cachedDirectoryReplacementAutomaticModeCopiesOnCI() async throws {
        try await Environment.$values.withValue(["CI": "1"]) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let nested = source.appendingPathComponent("nested")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: nested.appendingPathComponent("file.txt")
                )

                try await fileSystem.replaceWithCachedDirectory(
                    source: source, destination: destination
                )

                #expect(fileSystem.isDirectoryAndNotSymlink(destination))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath)
                )
                let data = try await fileSystem.readFile(at: destination.appendingPathComponent("nested/file.txt").absolutePath)
                #expect(String(data: data, encoding: .utf8) == "value")
            }
        }
    }

    @Test
    func cachedDirectoryReplacementAutomaticModeSymlinksOutsideCI() async throws {
        try await Environment.$values.withValue([:]) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let nested = source.appendingPathComponent("nested")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: nested.appendingPathComponent("file.txt")
                )

                try await fileSystem.replaceWithCachedDirectory(
                    source: source, destination: destination
                )

                #expect(!(fileSystem.isDirectoryAndNotSymlink(destination)))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath)
                )
                let data = try await fileSystem.readFile(at: destination.appendingPathComponent("nested/file.txt").absolutePath)
                #expect(String(data: data, encoding: .utf8) == "value")
            }
        }
    }

    @Test
    func registryDownloadReplacementAutomaticModeSymlinksContentsOutsideCI() async throws {
        try await Environment.$values.withValue([:]) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let nested = source.appendingPathComponent("nested")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: nested.appendingPathComponent("file.txt"))
                try await fileSystem.atomicWrite(
                    "manifest", to: source.appendingPathComponent("Package.swift"))

                try await fileSystem.replaceWithRegistryDownloadDirectory(
                    source: source, destination: destination)

                #expect(fileSystem.isDirectoryAndNotSymlink(destination))
                #expect(!(fileSystem.isDirectoryAndNotSymlink(destination.appendingPathComponent("nested"))))
                #expect(
                    !(fileSystem.isDirectoryAndNotSymlink(
                        destination.appendingPathComponent("Package.swift"))))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath))
                let data = try await fileSystem.readFile(at: destination.appendingPathComponent("nested/file.txt").absolutePath)
                #expect(String(data: data, encoding: .utf8) == "value")
            }
        }
    }

    @Test
    func registryDownloadReplacementAutomaticModeCopiesOnContinuousIntegration() async throws {
        try await Environment.$values.withValue(["CI": "1"]) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let nested = source.appendingPathComponent("nested")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: nested.appendingPathComponent("file.txt"))

                try await fileSystem.replaceWithRegistryDownloadDirectory(
                    source: source, destination: destination)

                #expect(fileSystem.isDirectoryAndNotSymlink(destination))
                #expect(fileSystem.isDirectoryAndNotSymlink(destination.appendingPathComponent("nested")))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath))
            }
        }
    }

    @Test
    func registryDownloadReplacementSymlinksContentsWhenConfigured() async throws {
        try await Environment.withCachedDirectoryMaterialization(.symlink) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let nested = source.appendingPathComponent("nested")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: nested.appendingPathComponent("file.txt"))

                try await fileSystem.replaceWithRegistryDownloadDirectory(
                    source: source, destination: destination)

                #expect(fileSystem.isDirectoryAndNotSymlink(destination))
                #expect(!(fileSystem.isDirectoryAndNotSymlink(destination.appendingPathComponent("nested"))))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath))
            }
        }
    }

    @Test
    func cachedDirectoryReplacementSymlinksOnCIWhenConfigured() async throws {
        try await Environment.$values.withValue([
            "CI": "1",
        ]) {
            try await Environment.withCachedDirectoryMaterialization(.symlink) {
                try await withTemporaryDirectory { root in
                    let source = root.appendingPathComponent("source")
                    let nested = source.appendingPathComponent("nested")
                    let destination = root.appendingPathComponent("destination")
                    try await fileSystem.makeDirectory(at: nested.absolutePath, options: [.createTargetParentDirectories])
                    try await fileSystem.atomicWrite(
                        "value", to: nested.appendingPathComponent("file.txt")
                    )

                    try await fileSystem.replaceWithCachedDirectory(
                        source: source, destination: destination
                    )

                    #expect(!(fileSystem.isDirectoryAndNotSymlink(destination)))
                    #expect(
                        try await fileSystem.exists(destination.appendingPathComponent("nested/file.txt").absolutePath)
                    )
                }
            }
        }
    }

    @Test
    func cachedDirectoryReplacementCopiesOutsideCIWhenConfigured() async throws {
        try await Environment.withCachedDirectoryMaterialization(.copy) {
            try await withTemporaryDirectory { root in
                let source = root.appendingPathComponent("source")
                let destination = root.appendingPathComponent("destination")
                try await fileSystem.makeDirectory(at: source.absolutePath, options: [.createTargetParentDirectories])
                try await fileSystem.atomicWrite(
                    "value", to: source.appendingPathComponent("file.txt")
                )

                try await fileSystem.replaceWithCachedDirectory(
                    source: source, destination: destination
                )

                #expect(fileSystem.isDirectoryAndNotSymlink(destination))
                #expect(
                    try await fileSystem.exists(destination.appendingPathComponent("file.txt").absolutePath)
                )
            }
        }
    }

    @Test
    func ciDetectionMatchesAubeEnvironmentLogic() {
        Environment.$values.withValue([:]) {
            #expect(!Environment.isCI)
        }
        Environment.$values.withValue(["CI": ""]) {
            #expect(Environment.isCI)
        }
        Environment.$values.withValue(["GITHUB_RUN_ID": "123"]) {
            #expect(Environment.isCI)
        }
        Environment.$values.withValue(["BUILD_NUMBER": "123"]) {
            #expect(Environment.isCI)
        }
    }

    @Test
    func temporaryDirectoryAndFileSafeNameUseScopedPaths() async throws {
        try await withTemporaryDirectory { root in
            let temp = try await fileSystem.temporaryDirectory(in: root)

            #expect(temp.path.hasPrefix(root.path))
            #expect(try await fileSystem.exists(temp.absolutePath))
            #expect(SafeFileName.make("a/b:c") == "a_b_c")
        }
    }

    @Test
    func netrcCredentialBeatsGitHubEnvToken() {
        let credential = RegistryCredential(user: "x-access-token", password: "harbor-token")
        let header = HTTPAuthorization.prioritizedHeader(
            isGitHub: true,
            netrcCredential: credential,
            gitHubEnvToken: "ghs_repo_scoped_token"
        )

        let expected = "Basic " + Data("x-access-token:harbor-token".utf8).base64EncodedString()
        #expect(header == expected)
    }

    @Test
    func gitHubEnvTokenUsedWhenNoNetrcCredential() {
        let header = HTTPAuthorization.prioritizedHeader(
            isGitHub: true,
            netrcCredential: nil,
            gitHubEnvToken: "ghs_repo_scoped_token"
        )

        #expect(header == "Bearer ghs_repo_scoped_token")
    }

    @Test
    func gitHubEnvTokenIgnoredForNonGitHubHostWithoutNetrc() {
        #expect(
            HTTPAuthorization.prioritizedHeader(
                isGitHub: false,
                netrcCredential: nil,
                gitHubEnvToken: "ghs_repo_scoped_token"
            ) == nil
        )
    }

    @Test
    func realpathFollowsSymlinksAndKeepsThePathWhenItCannotResolve() async throws {
        try await withTemporaryDirectory { directory in
            let target = directory.appendingPathComponent("Target")
            try await fileSystem.makeDirectory(
                at: target.absolutePath, options: [.createTargetParentDirectories])
            let link = directory.appendingPathComponent("Link")
            try await fileSystem.createSymbolicLink(from: link.absolutePath, to: target.absolutePath)
            let absent = directory.appendingPathComponent("Absent/Deep")

            #expect(
                PathCanonicalizer.realpath(link).path
                    == PathCanonicalizer.realpath(directory).appendingPathComponent("Target").path)
            // Nothing to resolve: the caller still needs the path it asked about, not a
            // truncated prefix of it.
            #expect(PathCanonicalizer.realpath(absent).path == absent.standardizedFileURL.path)
        }
    }
}

private actor CallCounter {
    private(set) var calls: [String: Int] = [:]

    func record(_ key: String) {
        calls[key, default: 0] += 1
    }
}

struct AsyncMemoTests {
    @Test
    func concurrentCallersShareASingleComputation() async {
        let memo = AsyncMemo<String, String?>()
        let counter = CallCounter()

        let values = await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    await memo.value(for: "github.com") {
                        await counter.record("github.com")
                        await Task.yield()
                        return "token"
                    }
                }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        #expect(values.count == 32)
        #expect(values.allSatisfy { $0 == "token" })
        #expect(await counter.calls["github.com"] == 1)
    }

    @Test
    func nilResultsAreMemoisedRatherThanRecomputed() async {
        // Discovering that there is no usable credential costs a subprocess and a network
        // round trip, and restores ask once per package, so the negative answer has to stick.
        let memo = AsyncMemo<String, String?>()
        let counter = CallCounter()

        for _ in 0 ..< 3 {
            let value = await memo.value(for: "github.com") {
                await counter.record("github.com")
                return nil
            }
            #expect(value == nil)
        }

        #expect(await counter.calls["github.com"] == 1)
    }

    @Test
    func distinctKeysAreComputedIndependently() async {
        let memo = AsyncMemo<String, String?>()
        let counter = CallCounter()

        let first = await memo.value(for: "gitlab.com") {
            await counter.record("gitlab.com")
            return "gitlab"
        }
        let second = await memo.value(for: "gitlab.example.com") {
            await counter.record("gitlab.example.com")
            return "self-hosted"
        }

        #expect(first == "gitlab")
        #expect(second == "self-hosted")
        #expect(await counter.calls["gitlab.com"] == 1)
        #expect(await counter.calls["gitlab.example.com"] == 1)
    }
}
