import SwiftUI

@MainActor
final class AtlasPresencePreviewData: ObservableObject {
    private var sequence = 0
    private var location: [String: String] = [:]
    private var waiting: CheckedContinuation<Data, Never>?
    lazy var model = AtlasPresence { [self] action in
        switch action["action"] as? String {
        case "open": return Data("{\"connection\":\"preview-only\"}".utf8)
        case "update":
            location = [:]
            for field in ["resource", "id"] {
                if let value = action[field] as? String { location[field] = value }
            }
            sequence += 1
            waiting?.resume(returning: snapshot())
            waiting = nil
            return Data("{\"updated\":true}".utf8)
        case "next":
            if (action["after"] as? UInt64 ?? 0) < sequence { return snapshot() }
            return await withCheckedContinuation { waiting = $0 }
        default:
            sequence += 1
            waiting?.resume(returning: snapshot())
            waiting = nil
            return Data("{\"closed\":true}".utf8)
        }
    }

    private func snapshot() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "location": location, "self_id": "preview-self",
            "people": [
                ["id": "online", "name": "Alex Morgan", "email": "alex@example.org", "online": true,
                 "here": !location.isEmpty && !ProcessInfo.processInfo.arguments.contains("--nobody-here")],
                ["id": "offline", "name": "Sam Rivera", "email": "sam@example.org", "online": false, "here": false]
            ]
        ])
    }
}
