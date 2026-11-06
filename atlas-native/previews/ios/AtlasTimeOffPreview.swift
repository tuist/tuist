import Foundation
import SwiftUI

@MainActor
final class AtlasTimeOffPreviewData: ObservableObject {
    private var requests: [[String: Any]] = [[
        "id": "01922cc0-0000-7000-8000-000000000001", "starts_on": "2027-06-07", "ends_on": "2027-06-11",
        "status": "pending", "working_days": 5, "missing_years": [],
    ]]

    func request(_ action: [String: Any]) async throws -> Data {
        let operation = action["action"] as? String
        if operation != "list" {
            if ProcessInfo.processInfo.arguments.contains("--fail-holiday-save") {
                throw NSError(domain: "preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Preview save failed. Your dates are still here."])
            }
            let id = action["id"] as? String
            if operation == "cancel", let index = requests.firstIndex(where: { $0["id"] as? String == id }) {
                requests[index]["status"] = "cancelled"
            } else {
                let booking: [String: Any] = [
                    "id": id ?? UUID().uuidString, "starts_on": action["starts_on"] ?? "2027-06-07",
                    "ends_on": action["ends_on"] ?? "2027-06-11", "status": "pending", "working_days": 5, "missing_years": [],
                ]
                if let index = requests.firstIndex(where: { $0["id"] as? String == id }) {
                    requests[index] = booking
                } else { requests.insert(booking, at: 0) }
            }
            return Data("{}".utf8)
        }
        let overview: [String: Any] = [
            "requests": ["items": requests, "page": 1, "total_pages": 1, "total_count": requests.count],
            "public_holidays": ["items": [["id": "holiday", "name": "Christmas Day", "date": "2027-12-25"]],
                                "page": 1, "total_pages": 1, "total_count": 1],
        ]
        return try JSONSerialization.data(withJSONObject: overview)
    }
}
