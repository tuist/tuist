import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Helpers for the existing string-valued custom metadata contract, not a second wire representation.
public enum BuildMetadata {
    public static func observations(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let process = ProcessInfo.processInfo
        var values: [String: String] = [
            "tuist.cpu.available_processors": String(process.activeProcessorCount),
            "tuist.memory.total_bytes": String(process.physicalMemory),
            "tuist.process.locale": Locale.current.identifier,
        ]
        #if os(macOS)
            values["tuist.os.type"] = "darwin"
            let version = process.operatingSystemVersion
            values["tuist.os.version"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #elseif os(Linux)
            values["tuist.os.type"] = "linux"
        #elseif os(Windows)
            values["tuist.os.type"] = "windows"
            let version = process.operatingSystemVersion
            values["tuist.os.version"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
        #if arch(arm64)
            values["tuist.host.arch"] = "arm64"
        #elseif arch(x86_64)
            values["tuist.host.arch"] = "x86_64"
        #endif
        values["tuist.ci.job"] = environment["GITHUB_JOB"] ?? environment["CI_JOB_NAME"]
        values["tuist.ci.runner_environment"] = environment["RUNNER_ENVIRONMENT"]
        if environment["TUIST_BUILD_METADATA_RUNNER_NAME"] == "1" {
            values["tuist.ci.runner_name"] = environment["RUNNER_NAME"] ?? environment["CI_RUNNER_DESCRIPTION"]
                ?? environment["BUILDKITE_AGENT_NAME"]
        }
        return values.filter { !$0.value.isEmpty && $0.value.utf8.count <= 500 }
    }

    public static func explicitValues(environment: [String: String]) -> [String: String] {
        Dictionary(environment.compactMap { key, value in
            guard key.hasPrefix("TUIST_BUILD_VALUE_") else { return nil }
            return (String(key.dropFirst("TUIST_BUILD_VALUE_".count)).lowercased(), value)
        }, uniquingKeysWith: { first, _ in first })
    }

    public static func merge(explicit: [String: String], observations: [String: String], limit: Int) -> [String: String] {
        var result = explicit
        for key in observations.keys.sorted() where result.count < limit && result[key] == nil {
            result[key] = observations[key]
        }
        return result
    }

    public static func values(
        explicit: [String: String],
        observations: [String: String],
        serverURL: URL
    ) async -> [String: String] {
        let count = Set(explicit.keys).union(observations.keys).count
        let limit = count > 20 ? await discoverLimit(serverURL: serverURL) : 20
        return merge(explicit: explicit, observations: observations, limit: limit)
    }

    static func discoveryURL(serverURL: URL) -> URL? {
        guard var components = URLComponents(
            url: serverURL.appendingPathComponent("api/metadata/limits"), resolvingAgainstBaseURL: true
        ) else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url
    }

    public static func discoverLimit(serverURL: URL) async -> Int {
        guard let url = discoveryURL(serverURL: serverURL) else { return 20 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration, delegate: NoMetadataRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let header = response.value(forHTTPHeaderField: "x-tuist-custom-metadata-max-values"),
                  let limit = Int(header), (20 ... 64).contains(limit)
            else { return 20 }
            return limit
        } catch {
            return 20
        }
    }
}

private final class NoMetadataRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
