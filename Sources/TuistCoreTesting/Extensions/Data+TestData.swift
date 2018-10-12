import Foundation

public extension Data {
    public static func testJson(_ json: Any) throws -> Data {
        return try JSONSerialization.data(withJSONObject: json, options: [])
    }
}
