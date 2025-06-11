import Foundation

extension NSError {
    public static func test() -> NSError {
        NSError(domain: "test", code: 1, userInfo: nil)
    }
}
