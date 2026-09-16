import GRPCCore
import GRPCNIOTransportHTTP2
import Testing

@testable import TuistREAPI

struct RemoteAssetProbeServiceTests {
    private struct FetchService: Build_Bazel_Remote_Asset_V1_Fetch.ServiceProtocol {
        var code: RPCError.Code?
        var delay: Duration = .zero

        func fetchBlob(
            request: ServerRequest<Build_Bazel_Remote_Asset_V1_FetchBlobRequest>,
            context _: ServerContext
        ) async throws -> ServerResponse<Build_Bazel_Remote_Asset_V1_FetchBlobResponse> {
            #expect(request.message.instanceName == "project")
            #expect(request.message.unknownFields.data.isEmpty)
            #expect(Array(request.metadata[stringValues: "authorization"]) == ["Bearer token"])
            #expect(Array(request.metadata[stringValues: "x-tuist-account-handle"]) == ["account"])
            try await Task.sleep(for: delay)
            if let code { throw RPCError(code: code, message: "test response") }
            return ServerResponse(message: .init())
        }
    }

    @Test(arguments: [
        RPCError.Code.invalidArgument,
        .unimplemented,
        .unauthenticated,
        .permissionDenied,
        .unavailable,
        .internalError,
    ])
    func only_invalid_argument_confirms_support(code: RPCError.Code) async throws {
        try await withServer(services: [FetchService(code: code)]) { endpoint in
            let available = await RemoteAssetProbeService().isAvailable(
                endpoint: endpoint, accountHandle: "account", instanceName: "project", token: "token"
            )
            #expect(available == (code == .invalidArgument))
        }
    }

    @Test
    func missing_route_does_not_enable_downloader() async throws {
        try await withServer(services: []) { endpoint in
            #expect(await !RemoteAssetProbeService().isAvailable(
                endpoint: endpoint, accountHandle: "account", instanceName: "project", token: "token"
            ))
        }
    }

    @Test
    func unexpected_success_does_not_enable_downloader() async throws {
        try await withServer(services: [FetchService(code: nil)]) { endpoint in
            #expect(await !RemoteAssetProbeService().isAvailable(
                endpoint: endpoint, accountHandle: "account", instanceName: "project", token: "token"
            ))
        }
    }

    @Test
    func deadline_bounds_a_stalled_probe() async throws {
        try await withServer(services: [FetchService(code: .invalidArgument, delay: .seconds(2))]) { endpoint in
            let clock = ContinuousClock()
            let start = clock.now
            #expect(await !RemoteAssetProbeService(timeout: .milliseconds(100)).isAvailable(
                endpoint: endpoint, accountHandle: "account", instanceName: "project", token: "token"
            ))
            #expect(start.duration(to: clock.now) < .seconds(5))
        }
    }

    private func withServer(
        services: [any RegistrableRPCService],
        body: @Sendable (GRPCEndpoint) async throws -> Void
    ) async throws {
        try await withGRPCServer(
            transport: .http2NIOPosix(address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext),
            services: services
        ) { server in
            let address = try #require(try await server.listeningAddress?.ipv4)
            try await body(GRPCEndpoint(host: address.host, explicitPort: address.port, isTLS: false))
        }
    }
}
