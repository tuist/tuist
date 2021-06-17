import Foundation
@testable import TuistCore

public extension LabResponseError.Error {
    static func test(code: String = "Code", message: String = "Message") -> LabResponseError.Error {
        .init(code: code, message: message)
    }
}

public extension LabResponseError {
    static func test(status: String = "Error status", errors: [Error]? = [.test()]) -> LabResponseError {
        .init(status: status, errors: errors)
    }
}
