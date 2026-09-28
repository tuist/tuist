import Foundation

/// Where a build's remote cache traffic was served from, as the CAS proxy
/// recorded it from Kura's `x-kura-region` / `x-kura-node` response headers.
public struct CacheServing: Encodable, Sendable, Equatable {
    /// The region that answered most of the build's recorded cache requests.
    public let region: String
    /// The node in that region that answered most of them.
    public let node: String
    /// When the oldest connection that region answered on was established
    /// (`yyyy-MM-dd'T'HH:mm:ss.SSS`, UTC), or nil when unknown.
    public let connected_at: String?
    /// How long that connection had been open when the build started, 0 when
    /// it opened during the build. The CAS proxy renews connections after its
    /// endpoint freshness window and on network changes, so a small value
    /// rules out a connection the proxy kept from an earlier network.
    public let connected_before_build_seconds: Int?
    /// Requests that region answered.
    public let region_requests: Int
    /// Requests whose answering region was recorded at all.
    public let observed_requests: Int

    /// `buildStartedAt` is the build's start as Unix seconds.
    static func summarize(_ entries: [ServedByEntry], buildStartedAt: Double? = nil) -> CacheServing? {
        guard !entries.isEmpty else { return nil }
        let byRegion = Dictionary(grouping: entries, by: \.region)
        guard let (region, answered) = byRegion.max(by: { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count
        }) else { return nil }
        let byNode = Dictionary(grouping: answered, by: \.node)
        let node = byNode.max(by: { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count
        })?.key ?? ""
        // The same fixed-width UTC text sorts chronologically.
        let connectedAt = answered.map(\.connectedAt).filter { !$0.isEmpty }.min()
        let connectedBeforeBuild: Int? = connectedAt.flatMap { connectedAt in
            guard let buildStartedAt, let connected = createdAtFormatter.date(from: connectedAt) else { return nil }
            return max(0, Int((buildStartedAt - connected.timeIntervalSince1970).rounded(.down)))
        }
        return CacheServing(
            region: region,
            node: node,
            connected_at: connectedAt,
            connected_before_build_seconds: connectedBeforeBuild,
            region_requests: answered.count,
            observed_requests: entries.count
        )
    }
}

/// The text form `cas_analytics.db` stores times in.
private let createdAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return formatter
}()

struct ServedByEntry: Sendable, Equatable {
    let region: String
    let node: String
    let connectedAt: String
}
