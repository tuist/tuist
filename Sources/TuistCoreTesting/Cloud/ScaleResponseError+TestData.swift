import Foundation
@testable import TuistCore

public extension ScaleResponseError.Error {
    static func test(code: String = "Code", message: String = "Message") -> ScaleResponseError.Error {
        .init(code: code, message: message)
    }
}

public extension ScaleResponseError {
    static func test(status: String = "Status", errors: [Error]? = [.test()]) -> ScaleResponseError {
        .init(status: status, errors: errors)
    }
}
