import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Mockable
import TuistLogging

@Mockable
public protocol RemoteCacheProbing: Sendable {
    /// Probes a remote cache endpoint by issuing the REAPI `GetCapabilities` call Bazel
    /// performs on start-up. It validates that the endpoint is reachable over gRPC, that
    /// TLS terminates correctly, and that the server authorizes the request and responds
    /// without an error. Throws a ``RemoteCacheProbeError`` when the endpoint is not usable.
    func probe(endpoint: GRPCEndpoint, accountHandle: String, instanceName: String, token: String) async throws
}

public struct RemoteCacheProbeService: RemoteCacheProbing {
    /// Each attempt allows the activation gateway its 20-second wait plus connection setup.
    private static let probeTimeout: Duration = .seconds(30)

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func probe(endpoint: GRPCEndpoint, accountHandle: String, instanceName: String, token: String) async throws {
        Logger.current.debug("Probing remote cache availability at \(endpoint.authority) (GetCapabilities)")

        let transport = try await REAPITransport.make(endpoint: endpoint, fileSystem: fileSystem)

        var options = CallOptions.defaults
        options.timeout = Self.probeTimeout

        var metadata = Metadata()
        metadata.addString("Bearer \(token)", forKey: "authorization")
        metadata.addString(accountHandle, forKey: "x-tuist-account-handle")

        let request = Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest.with {
            $0.instanceName = instanceName
        }

        do {
            try await withGRPCClient(transport: transport) { client in
                let capabilities = Build_Bazel_Remote_Execution_V2_Capabilities.Client(wrapping: client)
                for attempt in 0 ..< 4 {
                    do {
                        _ = try await capabilities.getCapabilities(request, metadata: metadata, options: options)
                        return
                    } catch let error as RPCError {
                        guard attempt < 3, [.unavailable, .resourceExhausted].contains(error.code) else { throw error }
                        try await Task.sleep(for: .seconds(2))
                    }
                }
            }
        } catch let error as RPCError {
            throw RemoteCacheProbeError.unavailable(
                endpoint: endpoint.authority,
                code: "\(error.code)",
                message: error.message
            )
        } catch {
            throw RemoteCacheProbeError.unreachable(endpoint: endpoint.authority, underlyingError: error)
        }

        Logger.current.debug("Remote cache at \(endpoint.authority) is reachable")
    }
}

public enum RemoteCacheProbeError: LocalizedError, Equatable {
    case unreachable(endpoint: String, underlyingError: any Error)
    case unavailable(endpoint: String, code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .unreachable(endpoint, underlyingError):
            return
                "Could not establish a connection with the remote cache at \(endpoint): \(underlyingError.localizedDescription)"
        case let .unavailable(endpoint, code, message):
            return "The remote cache at \(endpoint) is not available (\(code)): \(message)"
        }
    }

    public static func == (lhs: RemoteCacheProbeError, rhs: RemoteCacheProbeError) -> Bool {
        switch (lhs, rhs) {
        // `underlyingError` is `any Error` (not Equatable); two unreachable errors are
        // considered equal when they point at the same endpoint.
        case let (.unreachable(lhsEndpoint, _), .unreachable(rhsEndpoint, _)):
            return lhsEndpoint == rhsEndpoint
        case let (
            .unavailable(lhsEndpoint, lhsCode, lhsMessage),
            .unavailable(rhsEndpoint, rhsCode, rhsMessage)
        ):
            return lhsEndpoint == rhsEndpoint && lhsCode == rhsCode && lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
