/// Connection coordinates for a gRPC endpoint: a resolved host, whether the connection is
/// secured with TLS, and the port the URL explicitly requested (if any).
///
/// It is the single source of truth for both probing the endpoint and rendering the gRPC URL
/// that is handed to Bazel, so the two can never disagree about where Bazel will connect. It
/// intentionally stores `isTLS` rather than a scheme string: that is the property the transport
/// consumes (`.tls` vs `.plaintext`), and the `grpc`/`grpcs` scheme is derived from it.
public struct GRPCEndpoint: Equatable, Sendable {
    public let host: String
    /// The port the cache URL specified, or `nil` when it omitted one.
    public let explicitPort: Int?
    public let isTLS: Bool

    public init(host: String, explicitPort: Int?, isTLS: Bool) {
        self.host = host
        self.explicitPort = explicitPort
        self.isTLS = isTLS
    }

    /// The port to connect to, applying the gRPC TLS/plaintext defaults when the URL omitted one.
    public var port: Int {
        explicitPort ?? (isTLS ? 443 : 80)
    }

    public var scheme: String {
        isTLS ? "grpcs" : "grpc"
    }

    /// `host:port` using the resolved port — what the probe actually connects to.
    public var authority: String {
        "\(host):\(port)"
    }

    /// The gRPC URL for Bazel's `--remote_cache`. The explicit port is preserved and an omitted
    /// one is left out so Bazel applies its own default, matching the resolved `port`.
    public var url: String {
        let hostPort = explicitPort.map { "\(host):\($0)" } ?? host
        return "\(scheme)://\(hostPort)"
    }
}
