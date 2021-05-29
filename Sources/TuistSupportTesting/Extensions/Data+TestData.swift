import Foundation

public extension Data {
    static func testJson(_ json: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [])
    }
}
