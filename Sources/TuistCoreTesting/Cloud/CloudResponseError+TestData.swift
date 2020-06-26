import Foundation
@testable import TuistCore

public extension CloudResponseError.Error {
    static func test(code: String = "Code", message: String = "Message") -> CloudResponseError.Error {
        .init(code: code, message: message)
    }
}

public extension CloudResponseError {
    static func test(status: String = "Status", errors: [Error]? = [.test()]) -> CloudResponseError {
        .init(status: status, errors: errors)
    }
}
