import Foundation

/// Optional deployment metadata, never a substitute for API capability checks.
public struct AppServerInfoService: Sendable {
    static let maximumResponseSize = 64 * 1024
    private static let session = makeSession()
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(perform: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.perform = perform ?? { try await Self.load($0, session: Self.session) }
    }

    public func version(for serverURL: URL) async -> String? {
        var request = URLRequest(url: serverURL.appending(path: ".well-known/tuist"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            try Task.checkCancellation()
            let (data, response) = try await perform(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.url == request.url,
                  data.count <= Self.maximumResponseSize,
                  let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
                  let version = metadata.version?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !version.isEmpty, version.count <= 128,
                  version.rangeOfCharacter(from: .controlCharacters) == nil
            else { return nil }
            return version
        } catch {
            return nil
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: ServerInfoSessionDelegate(), delegateQueue: nil)
    }

    static func load(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200, response.url == request.url
        else { return (Data(), response) }
        guard response.expectedContentLength <= maximumResponseSize else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseSize else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }

    private struct Metadata: Decodable {
        let version: String?
    }
}

private final class ServerInfoSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
