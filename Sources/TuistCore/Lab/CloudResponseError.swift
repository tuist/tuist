import Foundation
import TuistSupport

public struct CloudResponseError: Decodable, LocalizedError, Equatable {
    public var status: String
    public var errors: [Error]?

    public struct Error: Decodable, Equatable {
        var code: String
        var message: String
    }

    public var errorDescription: String? {
        errors?.map { $0.message.capitalizingFirstLetter() }.joined(separator: "\n")
    }
}

public struct CloudEmptyResponseError: Decodable, LocalizedError, Equatable {
    public init() {}
}
