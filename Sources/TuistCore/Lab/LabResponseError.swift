import Foundation
import TuistSupport

public struct LabResponseError: Decodable, LocalizedError, Equatable {
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

public struct LabHEADResponseError: Decodable, LocalizedError, Equatable {
    public init() {}
}
