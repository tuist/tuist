import GRPCCore
import GRPCNIOTransportHTTP2
import Testing
import TuistEnvironmentTesting
@testable import TuistREAPI

struct RemoteCacheProbeServiceTests {
    @Test(.withMockedEnvironment(), arguments: [RPCError.Code.unavailable, .resourceExhausted, .permissionDenied], [false, true])
    func capabilityProbeRecoversFromColdActivation(code: RPCError.Code, persistent: Bool) async throws {
        let state = ActivationProbeState(code: code, failures: persistent ? .max : 1)
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [ActivationCapabilities(state: state)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let endpoint = GRPCEndpoint(host: "127.0.0.1", explicitPort: try #require(address.ipv4?.port), isTLS: false)
            if code == .permissionDenied || persistent {
                await #expect(throws: RemoteCacheProbeError.self) {
                    try await RemoteCacheProbeService().probe(
                        endpoint: endpoint,
                        accountHandle: "account",
                        instanceName: "project",
                        token: "token"
                    )
                }
                #expect(await state.attempts == (code == .permissionDenied ? 1 : 4))
            } else {
                try await RemoteCacheProbeService().probe(
                    endpoint: endpoint,
                    accountHandle: "account",
                    instanceName: "project",
                    token: "token"
                )
                #expect(await state.attempts == 2)
            }
        }
    }
}

private actor ActivationProbeState {
    let code: RPCError.Code
    var attempts = 0
    let failures: Int
    init(code: RPCError.Code, failures: Int) {
        self.code = code
        self.failures = failures
    }

    func probe() throws {
        attempts += 1
        if attempts <= failures { throw RPCError(code: code, message: "cache activation pending") }
    }
}

private struct ActivationCapabilities: Build_Bazel_Remote_Execution_V2_Capabilities.SimpleServiceProtocol {
    let state: ActivationProbeState
    func getCapabilities(
        request _: Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_ServerCapabilities {
        try await state.probe()
        return .with { $0.cacheCapabilities.digestFunctions = [.sha256] }
    }
}
