import Foundation

struct LogStoreManifest: Codable {
    let logs: [String: ActivityLog]
}
