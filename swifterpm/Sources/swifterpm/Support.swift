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
        case .message(let message):
            return message
        }
    }
}

enum SystemProcess {
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
                message.isEmpty ? result.terminationStatus.description : message)
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
            !(200..<300).contains(httpResponse.statusCode)
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
            !(200..<300).contains(httpResponse.statusCode)
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
        if isGitHub(url), let token = nonEmpty(environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"]) {
            return bearerHeader(token)
        }

        if let netrcData = nonEmpty(environment["SWIFTPM_NETRC_DATA"]),
           let credential = RegistryNetrc(content: netrcData).credential(for: url)
        {
            return basicHeader(credential)
        }

        if let home = environment["HOME"] {
            let netrcPath = URL(fileURLWithPath: home).appendingPathComponent(".netrc")
            if let data = try? await fileSystem.readFile(at: netrcPath.absolutePath),
               let content = String(data: data, encoding: .utf8),
               let credential = RegistryNetrc(content: content).credential(for: url)
            {
                return basicHeader(credential)
            }
        }

        if isGitHub(url), let token = await GitHubAuth.token() {
            return bearerHeader(token)
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
            var results = Array<Output?>(repeating: nil, count: elements.count)

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
            path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH)
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
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data + Data("\n".utf8)
    }
}

enum SafeFileName {
    static func make(_ name: String) -> String {
        String(
            name.map { character in
                if character.isASCII
                    && (character.isLetter || character.isNumber || character == "-"
                        || character == "_"
                        || character == ".")
                {
                    return character
                }
                return "_"
            })
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
