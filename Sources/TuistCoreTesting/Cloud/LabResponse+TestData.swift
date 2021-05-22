import Foundation
@testable import TuistCore

extension LabResponse {
    static func test(status: String = "status", data: T) -> LabResponse<T> {
        LabResponse(status: status, data: data)
    }
}
