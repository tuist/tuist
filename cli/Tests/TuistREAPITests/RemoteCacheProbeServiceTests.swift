import GRPCCore
import GRPCNIOTransportHTTP2
import Testing
import TuistEnvironmentTesting
@testable import TuistREAPI

struct RemoteCacheProbeServiceTests {
    enum Consumer: CaseIterable {
        case probe, moduleCache

        func validate(endpoint: GRPCEndpoint) async throws {
            switch self {
            case .probe:
                try await RemoteCacheProbeService().probe(
                    endpoint: endpoint, accountHandle: "account", instanceName: "project", token: "token"
                )
            case .moduleCache:
                let client = try await REAPICacheClient(
                    endpoint: endpoint, accountHandle: "account", instanceName: "project"
                ) { "token" }
                try await client.validateCapabilities()
            }
        }
    }

    @Test(.withMockedEnvironment(), arguments: Consumer.allCases)
    func capabilityNegotiationWaitsForGatewayActivation(consumer: Consumer) async throws {
        // A real activation response can take 20 seconds, beyond the old module-cache deadline.
        let state = ActivationProbeState(code: .unavailable, failures: 1, firstResponseDelay: .seconds(20))
        try await withServer(state: state) { endpoint in
            try await consumer.validate(endpoint: endpoint)
            #expect(await state.attempts == 2)
        }
    }

    @Test(.withMockedEnvironment(), arguments: Consumer.allCases, [RPCError.Code.unavailable, .resourceExhausted])
    func capabilityNegotiationBoundsRetries(consumer: Consumer, code: RPCError.Code) async throws {
        let state = ActivationProbeState(code: code, failures: .max)
        try await withServer(state: state) { endpoint in
            await #expect(throws: (any Error).self) { try await consumer.validate(endpoint: endpoint) }
            #expect(await state.attempts == 4)
        }
    }

    @Test(.withMockedEnvironment(), arguments: Consumer.allCases, [
        RPCError.Code.unauthenticated, .permissionDenied, .invalidArgument, .deadlineExceeded,
    ])
    func capabilityNegotiationDoesNotRetryPermanentErrors(consumer: Consumer, code: RPCError.Code) async throws {
        let state = ActivationProbeState(code: code, failures: .max)
        try await withServer(state: state) { endpoint in
            await #expect(throws: (any Error).self) { try await consumer.validate(endpoint: endpoint) }
            #expect(await state.attempts == 1)
        }
    }

    @Test(.withMockedEnvironment(), arguments: Consumer.allCases)
    func cancellationStopsActivationRetries(consumer: Consumer) async throws {
        let state = ActivationProbeState(code: .unavailable, failures: .max)
        try await withServer(state: state) { endpoint in
            let validation = Task { try await consumer.validate(endpoint: endpoint) }
            await state.waitForAttempt()
            validation.cancel()
            await #expect(throws: (any Error).self) { try await validation.value }
            #expect(await state.attempts == 1)
        }
    }

    private func withServer(
        state: ActivationProbeState, operation: (GRPCEndpoint) async throws -> Void
    ) async throws {
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [ActivationCapabilities(state: state)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let endpoint = GRPCEndpoint(host: "127.0.0.1", explicitPort: try #require(address.ipv4?.port), isTLS: false)
            try await operation(endpoint)
        }
    }
}

private actor ActivationProbeState {
    let code: RPCError.Code
    var attempts = 0
    let failures: Int
    let firstResponseDelay: Duration
    private var started: CheckedContinuation<Void, Never>?

    init(code: RPCError.Code, failures: Int, firstResponseDelay: Duration = .zero) {
        self.code = code
        self.failures = failures
        self.firstResponseDelay = firstResponseDelay
    }

    func waitForAttempt() async {
        if attempts > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func probe() async throws {
        attempts += 1
        started?.resume()
        started = nil
        if attempts == 1 { try await Task.sleep(for: firstResponseDelay) }
        if attempts <= failures { throw RPCError(code: code, message: "cache activation pending") }
    }
}

private struct ActivationCapabilities: Build_Bazel_Remote_Execution_V2_Capabilities.ServiceProtocol {
    let state: ActivationProbeState
    func getCapabilities(
        request: ServerRequest<Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest>, context _: ServerContext
    ) async throws -> ServerResponse<Build_Bazel_Remote_Execution_V2_ServerCapabilities> {
        #expect(request.message.instanceName == "project")
        #expect(Array(request.metadata[stringValues: "authorization"]) == ["Bearer token"])
        #expect(Array(request.metadata[stringValues: "x-tuist-account-handle"]) == ["account"])
        try await state.probe()
        return ServerResponse(message: .with { $0.cacheCapabilities.digestFunctions = [.sha256] }, metadata: [:])
    }
}
