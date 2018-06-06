import Foundation

extension NSError {
    static func test() -> NSError {
        return NSError(domain: "test", code: 1, userInfo: nil)
    }
}
