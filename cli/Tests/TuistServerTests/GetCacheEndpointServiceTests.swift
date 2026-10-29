import Foundation
import Mockable
import Testing
import TuistEnvironment

#if canImport(Network)
    import Network
    import Synchronization
#endif

@testable import TuistServer

struct GetCacheEndpointServiceTests {
    #if canImport(Network)
        @Test(arguments: [200, 302, 307])
        func unsigned_endpoint_discovery_does_not_follow_redirects(status: Int) async throws {
            let server = try EndpointDiscoveryServer(status: status)
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "http://127.0.0.1:\(port)"))
            let credentials = MockServerCredentialsStoring()
            given(credentials).read(serverURL: .any).willReturn(nil)
            try await Environment.$current.withValue(Environment(variables: [:], arguments: [])) {
                try await ServerCredentialsStore.$current.withValue(credentials) {
                    try await ServerCacheAccessMode.$serverAllowsNetworkCacheAccess.withValue({ _ in true }) {
                        if status == 200 {
                            let result = try await GetCacheEndpointService().getCacheEndpoint(serverURL: url)
                            #expect(result.endpoint == "https://cache.example")
                        } else {
                            await #expect(throws: GetCacheEndpointServiceError.unknownError(status)) {
                                try await GetCacheEndpointService().getCacheEndpoint(serverURL: url)
                            }
                        }
                    }
                }
            }
            let requests = server.requests.withLock { $0 }
            #expect(requests.count == 1)
            #expect(requests.first?.hasPrefix("GET /api/cache/endpoint ") == true)
            #expect(requests.allSatisfy { !$0.lowercased().contains("authorization:") && !$0.lowercased().contains("cookie:") })
        }
    #endif

    @Test func reads_max_age_out_of_a_cache_control_value() {
        #expect(GetCacheEndpointService.maxAge(from: "private, max-age=3600") == 3600)
        #expect(GetCacheEndpointService.maxAge(from: "max-age=30") == 30)
        #expect(GetCacheEndpointService.maxAge(from: "private, Max-Age = 30") == 30)
    }

    @Test func has_no_max_age_when_the_server_does_not_give_one() {
        #expect(GetCacheEndpointService.maxAge(from: "max-age=-1") == nil)
        #expect(GetCacheEndpointService.maxAge(from: "max-age=inf") == nil)
        #expect(GetCacheEndpointService.maxAge(from: nil) == nil)
        #expect(GetCacheEndpointService.maxAge(from: "no-store") == nil)
        #expect(GetCacheEndpointService.maxAge(from: "private, max-age=soon") == nil)
    }
}

#if canImport(Network)
    private final class EndpointDiscoveryServer: Sendable {
        let requests = Mutex<[String]>([])
        private let listener: NWListener
        private let status: Int
        private let queue = DispatchQueue(label: "dev.tuist.EndpointDiscoveryServer")

        init(status: Int) throws {
            self.status = status
            listener = try NWListener(using: .tcp, on: .any)
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                receive(connection, buffer: Data())
            }
            return try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        continuation.resume(returning: listener.port!.rawValue)
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() { listener.cancel() }

        private func receive(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.range(of: Data("\r\n\r\n".utf8)) != nil else {
                    if complete || error != nil { connection.cancel() }
                    else { receive(connection, buffer: buffer) }
                    return
                }
                let request = String(decoding: buffer, as: UTF8.self)
                requests.withLock { $0.append(request) }
                let redirected = request.hasPrefix("GET /redirected ")
                let body = #"{"endpoint":"https://cache.example"}"#
                let response = """
                HTTP/1.1 \(redirected ? 200 : status) Response\r
                Content-Type: application/json\r
                Content-Length: \(body.utf8.count)\r
                Location: http://localhost:\(listener.port!.rawValue)/redirected\r
                Connection: close\r
                \r
                \(body)
                """
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
#endif
