import Foundation

public extension NSError {
    static func test() -> NSError {
        NSError(domain: "test", code: 1, userInfo: nil)
    }
}
