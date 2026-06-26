import Foundation
import Subprocess

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

enum ToolError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

/// Reports every candidate location that was tried and how each failed, instead of only the
/// last error. The previous behaviour surfaced just `lastError`, which for an SSH-declared
/// dependency is always the trailing SSH candidate, masking whether the HTTPS fallback was
/// even attempted and why it failed. Listing each attempt makes the actual cause diagnosable.
enum GitFetchFailure {
    static func error(location: String, attempts: [(candidate: String, error: any Error)])
        -> ToolError
    {
        guard !attempts.isEmpty else {
            return ToolError.message("no source-control locations available for \(location)")
        }
        let details = attempts
            .map { "  - \($0.candidate): \($0.error)" }
            .joined(separator: "\n")
        return ToolError.message(
            "could not fetch any candidate location for \(location):\n\(details)"
        )
    }
}

enum SystemProcess {
    /// swifterpm invokes git non-interactively: output is captured and fetches run
    /// in parallel, so a built-in credential prompt (git opens /dev/tty directly)
    /// would block invisibly in any environment, not just CI. Force git to fail fast
    /// on a missing credential instead. Credential helpers, ssh-agent, and ~/.netrc
    /// are unaffected, so configured authentication still works.
    static let nonInteractiveGitEnvironment = ["GIT_TERMINAL_PROMPT": "0"]

    struct Result {
        let stdout: Data
        let stderr: Data

        var stdoutString: String {
            String(data: stdout, encoding: .utf8) ?? ""
        }

        var stderrString: String {
            String(data: stderr, encoding: .utf8) ?? ""
        }
    }

    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        forwardOutput: Bool = false,
        outputLimit: Int = 64 * 1024 * 1024
    ) async throws -> Result {
        if forwardOutput {
            let result = try await Subprocess.run(
                subprocessExecutable(executable),
                arguments: Arguments(arguments),
                environment: subprocessEnvironment(environment),
                workingDirectory: workingDirectory.map { FilePath($0.path) },
                output: .standardOutput,
                error: .standardError
            )

            guard result.terminationStatus.isSuccess else {
                throw ToolError.message(result.terminationStatus.description)
            }

            return Result(stdout: Data(), stderr: Data())
        }

        let result = try await Subprocess.run(
            subprocessExecutable(executable),
            arguments: Arguments(arguments),
            environment: subprocessEnvironment(environment),
            workingDirectory: workingDirectory.map { FilePath($0.path) },
            output: .bytes(limit: outputLimit),
            error: .bytes(limit: outputLimit)
        )

        guard result.terminationStatus.isSuccess else {
            let stderrText = String(data: Data(result.standardError), encoding: .utf8) ?? ""
            let stdoutText = String(data: Data(result.standardOutput), encoding: .utf8) ?? ""
            let message = stderrText.isEmpty ? stdoutText : stderrText
            throw ToolError.message(
                message.isEmpty ? result.terminationStatus.description : message
            )
        }

        return Result(stdout: Data(result.standardOutput), stderr: Data(result.standardError))
    }

    static func output(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        outputLimit: Int = 64 * 1024 * 1024
    ) async throws -> String {
        try await run(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            outputLimit: outputLimit
        ).stdoutString
    }

    private static func subprocessExecutable(_ executable: String) -> Executable {
        executable.contains("/") ? .path(FilePath(executable)) : .name(executable)
    }

    private static func subprocessEnvironment(_ environment: [String: String])
        -> Subprocess.Environment
    {
        guard !environment.isEmpty else { return .inherit }
        var overrides: [Subprocess.Environment.Key: String?] = [:]
        for (key, value) in environment {
            if let subprocessKey = Subprocess.Environment.Key(rawValue: key) {
                overrides[subprocessKey] = value
            }
        }
        return .inherit.updating(overrides)
    }
}

enum HTTPClient {
    static func defaultHeaders(for url: URL) async -> [String: String] {
        var headers = ["User-Agent": "swifterpm/0.1"]
        if let authorization = await HTTPAuthorization.header(for: url) {
            headers["Authorization"] = authorization
        }
        return headers
    }

    /// Headers for downloading a binary artifact archive. GitHub's release-asset
    /// endpoint returns asset metadata unless the request accepts the raw bytes.
    static func binaryArtifactHeaders(for url: URL) async -> [String: String] {
        var headers = await defaultHeaders(for: url)
        headers["Accept"] = "application/octet-stream"
        return headers
    }

    static func data(url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            throw ToolError.message("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
        }
        return data
    }

    static func download(url: URL, destination: URL, headers: [String: String] = [:]) async throws {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            try? await fileSystem.remove(downloaded.absolutePath)
            throw ToolError.message("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
        }

        let destinationPath = try destination.absolutePath
        try await fileSystem.makeDirectory(
            at: destinationPath.parentDirectory, options: [.createTargetParentDirectories]
        )
        try await fileSystem.replace(destinationPath, with: downloaded.absolutePath)
    }
}

enum HTTPAuthorization {
    static func header(for url: URL) async -> String? {
        let environment = ProcessInfo.processInfo.environment

        // Explicit, host-scoped credentials win over an ambient GitHub token. A
        // `machine api.github.com` entry in ~/.netrc (or SWIFTPM_NETRC_DATA) is a
        // deliberate per-host credential, so it must beat a generic GITHUB_TOKEN /
        // GH_TOKEN that may be scoped to an unrelated repository — otherwise a
        // repo-scoped CI token shadows the netrc credential that can actually read
        // a private release asset. This mirrors SwiftPM, whose download
        // AuthorizationProvider resolves netrc and never consults GITHUB_TOKEN.
        if let header = prioritizedHeader(
            isGitHub: isGitHub(url),
            netrcCredential: await netrcCredential(for: url, environment: environment),
            gitHubEnvToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"]
        ) {
            return header
        }

        if isGitHub(url), let token = await GitHubAuth.token() {
            return bearerHeader(token)
        }

        return nil
    }

    static func prioritizedHeader(
        isGitHub: Bool,
        netrcCredential: RegistryCredential?,
        gitHubEnvToken: String?
    ) -> String? {
        if let credential = netrcCredential {
            return basicHeader(credential)
        }
        if isGitHub, let token = nonEmpty(gitHubEnvToken) {
            return bearerHeader(token)
        }
        return nil
    }

    private static func netrcCredential(
        for url: URL,
        environment: [String: String]
    ) async -> RegistryCredential? {
        if let netrcData = nonEmpty(environment["SWIFTPM_NETRC_DATA"]),
           let credential = RegistryNetrc(content: netrcData).credential(for: url)
        {
            return credential
        }

        if let home = environment["HOME"] {
            let netrcPath = URL(fileURLWithPath: home).appendingPathComponent(".netrc")
            if let data = try? await fileSystem.readFile(at: netrcPath.absolutePath),
               let content = String(data: data, encoding: .utf8),
               let credential = RegistryNetrc(content: content).credential(for: url)
            {
                return credential
            }
        }

        return nil
    }

    private static func isGitHub(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com"
    }

    private static func basicHeader(_ credential: RegistryCredential) -> String {
        let token = Data("\(credential.user):\(credential.password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    private static func bearerHeader(_ token: String) -> String {
        "Bearer \(token)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum Hashing {
    static func stable(_ input: String) -> String {
        sha256Hex(Data(input.utf8))
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func shortRevision(_ revision: String) -> String {
        String(revision.prefix(12))
    }
}

private let defaultParallelism = max(4, min(32, ProcessInfo.processInfo.activeProcessorCount * 4))

enum ConcurrentTasks {
    static func map<Element: Sendable, Output: Sendable>(
        _ elements: [Element],
        maxConcurrentTasks: Int = defaultParallelism,
        operation: @Sendable @escaping (Element) async throws -> Output
    ) async throws -> [Output] {
        guard !elements.isEmpty else { return [] }
        let limit = max(1, min(maxConcurrentTasks, elements.count))

        return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var iterator = elements.enumerated().makeIterator()
            var activeTasks = 0
            var results = [Output?](repeating: nil, count: elements.count)

            while activeTasks < limit, let (index, element) = iterator.next() {
                group.addTask {
                    (index, try await operation(element))
                }
                activeTasks += 1
            }

            while activeTasks > 0 {
                guard let (index, result) = try await group.next() else { break }
                activeTasks -= 1
                results[index] = result

                if let (index, element) = iterator.next() {
                    group.addTask {
                        (index, try await operation(element))
                    }
                    activeTasks += 1
                }
            }

            var ordered: [Output] = []
            ordered.reserveCapacity(elements.count)
            for result in results {
                guard let result else {
                    throw ToolError.message("concurrent task result missing")
                }
                ordered.append(result)
            }
            return ordered
        }
    }

    static func forEach<Element: Sendable>(
        _ elements: [Element],
        maxConcurrentTasks: Int = defaultParallelism,
        operation: @Sendable @escaping (Element) async throws -> Void
    ) async throws {
        _ =
            try await map(elements, maxConcurrentTasks: maxConcurrentTasks, operation: operation)
                as [Void]
    }
}

final class PathLock: @unchecked Sendable {
    private let fd: Int32

    init(path: URL) throws {
        fd = open(
            path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
        )
        if fd < 0 {
            throw ToolError.message("failed to open lock \(path.path)")
        }
        if flock(fd, LOCK_EX) != 0 {
            close(fd)
            throw ToolError.message("failed to lock \(path.path)")
        }
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

extension PathLock {
    static func acquire(at path: URL) async throws -> PathLock {
        try await fileSystem.makeDirectory(
            at: path.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        return try await Task.detached {
            try PathLock(path: path)
        }.value
    }
}

enum JSONFormatter {
    static func prettyData(_ object: Any) throws -> Data {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return data + Data("\n".utf8)
    }
}

enum SafeFileName {
    static func make(_ name: String) -> String {
        String(
            name.map { character in
                if character.isASCII,
                   character.isLetter || character.isNumber || character == "-"
                   || character == "_"
                   || character == "."
                {
                    return character
                }
                return "_"
            }
        )
    }
}

enum SafePathComponent {
    static func make(_ name: String) -> String {
        let sanitized = SafeFileName.make(name)
        if sanitized.isEmpty || sanitized.allSatisfy({ $0 == "." }) {
            return "_"
        }
        return sanitized
    }
}

enum PathCanonicalizer {
    static func realpath(_ url: URL) -> URL {
        #if os(Windows)
            url.standardizedFileURL
        #else
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            #if canImport(Glibc)
                let resolved = Glibc.realpath(url.path, &buffer)
            #elseif canImport(Musl)
                let resolved = Musl.realpath(url.path, &buffer)
            #else
                let resolved = Darwin.realpath(url.path, &buffer)
            #endif
            if let resolved, let path = String(validatingCString: resolved) {
                return URL(fileURLWithPath: path)
            }
            return url.standardizedFileURL
        #endif
    }
}

extension URL {
    func appendingPathComponents(_ components: [String]) -> URL {
        components.reduce(self) { partial, component in
            partial.appendingPathComponent(component)
        }
    }
}
