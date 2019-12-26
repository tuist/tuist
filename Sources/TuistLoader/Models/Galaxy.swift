import Basic
import Foundation
import TuistSupport

public struct Galaxy: Equatable, Codable {
    // MARK: - Attributes

    public let token: String

    // MARK: - Init

    public init(token: String) {
        self.token = token
    }
}
