import Foundation
import TuistSupport

public struct CloudResponseError: Decodable, LocalizedError {
    public var status: String
    public var errors: [Error]?

    public struct Error: Decodable {
        var code: String
        var message: String
    }

    public var errorDescription: String? {
        errors?.map { $0.message.capitalizingFirstLetter() }.joined(separator: "\n")
    }
}
