import Foundation

public extension NSError {
    public static func test() -> NSError {
        return NSError(domain: "test", code: 1, userInfo: nil)
    }
}
