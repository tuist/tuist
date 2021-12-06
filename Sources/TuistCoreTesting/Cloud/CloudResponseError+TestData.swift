import Foundation
@testable import TuistCore

extension CloudResponseError.Error {
    public static func test(code: String = "Code", message: String = "Message") -> CloudResponseError.Error {
        .init(code: code, message: message)
    }
}

extension CloudResponseError {
    public static func test(status: String = "Error status", errors: [Error]? = [.test()]) -> CloudResponseError {
        .init(status: status, errors: errors)
    }
}
