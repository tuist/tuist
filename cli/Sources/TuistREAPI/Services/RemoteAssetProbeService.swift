import GRPCCore
import GRPCNIOTransportHTTP2
import Mockable
import TuistLogging

@Mockable
public protocol RemoteAssetProbing: Sendable {
    func isAvailable(endpoint: GRPCEndpoint, accountHandle: String, instanceName: String, token: String) async -> Bool
}

public struct RemoteAssetProbeService: RemoteAssetProbing {
    private let timeout: Duration

    public init() {
        timeout = .seconds(5)
    }

    init(timeout: Duration) {
        self.timeout = timeout
    }

    public func isAvailable(endpoint: GRPCEndpoint, accountHandle: String, instanceName: String, token: String) async -> Bool {
        do {
            let transport: HTTP2ClientTransport.Posix = try .http2NIOPosix(
                target: .dns(host: endpoint.host, port: endpoint.port),
                transportSecurity: endpoint.isTLS ? .tls : .plaintext
            )
            var options = CallOptions.defaults
            options.timeout = timeout
            var metadata = Metadata()
            metadata.addString("Bearer \(token)", forKey: "authorization")
            metadata.addString(accountHandle, forKey: "x-tuist-account-handle")

            // Remote Asset requires a URI. Omitting it exercises the actual gateway route
            // without fetching or storing anything, unlike a GetCapabilities-only check.
            let request = Build_Bazel_Remote_Asset_V1_FetchBlobRequest.with {
                $0.instanceName = instanceName
            }
            try await withGRPCClient(transport: transport) { client in
                let fetch = Build_Bazel_Remote_Asset_V1_Fetch.Client(wrapping: client)
                _ = try await fetch.fetchBlob(request, metadata: metadata, options: options)
            }
        } catch let error as RPCError where error.code == .invalidArgument {
            return !Task.isCancelled
        } catch {
            Logger.current.debug("Remote Asset probe did not confirm support at \(endpoint.authority)")
        }
        return false
    }
}
