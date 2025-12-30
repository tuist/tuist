import Foundation

extension Data {
    public static func testJson(_ json: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [])
    }
}
