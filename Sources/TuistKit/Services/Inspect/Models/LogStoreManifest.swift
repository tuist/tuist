import Foundation

public struct LogStoreManifest: Codable {
    public let logs: [String: ActivityLog]
}
