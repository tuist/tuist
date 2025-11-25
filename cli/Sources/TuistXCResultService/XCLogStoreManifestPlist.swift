import Foundation

struct XCLogStoreManifestPlist: Decodable {
    let logs: [String: Log]

    struct Log: Decodable {
        let fileName: String
        let timeStoppedRecording: Double
    }
}
