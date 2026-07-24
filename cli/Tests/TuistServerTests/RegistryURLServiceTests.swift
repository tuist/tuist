import Foundation
import Testing

@testable import TuistServer

struct RegistryURLServiceTests {
    @Test func returns_the_swift_ecosystem_configuration() async throws {
        // Given
        let server = RegistryDiscoveryURLProtocolServer(
            statusCode: 200,
            responseData: Data("""
            {
              "ecosystems": {
                "swift": {
                  "url": "https://registry.tuist.dev/swift",
                  "loginAPIPath": "/swift/login"
                }
              }
            }
            """.utf8)
        )
        let subject = RegistryURLService(urlSession: server.urlSession)

        // When
        let got = try await subject.registryConfiguration(serverURL: server.serverURL)

        // Then
        #expect(got == RegistryConfiguration(
            url: URL(string: "https://registry.tuist.dev/swift")!,
            loginAPIPath: "/swift/login"
        ))
    }

    @Test func returns_nil_when_the_endpoint_is_not_found() async throws {
        // Given
        let server = RegistryDiscoveryURLProtocolServer(statusCode: 404, responseData: Data())
        let subject = RegistryURLService(urlSession: server.urlSession)

        // When
        let got = try await subject.registryConfiguration(serverURL: server.serverURL)

        // Then
        #expect(got == nil)
    }

    @Test func returns_nil_when_no_swift_ecosystem_is_advertised() async throws {
        // Given
        let server = RegistryDiscoveryURLProtocolServer(
            statusCode: 200,
            responseData: Data(
                #"{ "ecosystems": { "gradle": { "url": "https://registry.tuist.dev/gradle", "loginAPIPath": "/gradle/login" } } }"#
                    .utf8
            )
        )
        let subject = RegistryURLService(urlSession: server.urlSession)

        // When
        let got = try await subject.registryConfiguration(serverURL: server.serverURL)

        // Then
        #expect(got == nil)
    }
}

private final class RegistryDiscoveryURLProtocolServer: Sendable {
    private let id = UUID().uuidString

    init(statusCode: Int, responseData: Data) {
        RegistryDiscoveryURLProtocol.register(id: id, statusCode: statusCode, responseData: responseData)
    }

    deinit {
        RegistryDiscoveryURLProtocol.unregister(id: id)
    }

    var serverURL: URL {
        URL(string: "https://tuist.dev?testID=\(id)")!
    }

    var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryDiscoveryURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct RegistryDiscoveryURLProtocolState {
    var statusCode: Int
    var responseData: Data
}

private final class RegistryDiscoveryURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var states: [String: RegistryDiscoveryURLProtocolState] = [:]
    private nonisolated(unsafe) static let lock = NSLock()

    static func register(id: String, statusCode: Int, responseData: Data) {
        lock.lock()
        defer { lock.unlock() }
        states[id] = RegistryDiscoveryURLProtocolState(statusCode: statusCode, responseData: responseData)
    }

    static func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        states[id] = nil
    }

    private static func state(for request: URLRequest) -> RegistryDiscoveryURLProtocolState? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "testID" })?.value
        else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return states[id]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        state(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let state = Self.state(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: state.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: state.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
