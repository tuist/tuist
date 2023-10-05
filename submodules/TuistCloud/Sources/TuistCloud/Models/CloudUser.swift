import Foundation

/// Cloud user
public struct CloudUser: Codable {
    public let id: Int
    public let name: String
    public let email: String

    public init(
        id: Int,
        name: String,
        email: String
    ) {
        self.id = id
        self.name = name
        self.email = email
    }
}

extension CloudUser {
    init(_ user: Components.Schemas.User) {
        id = Int(user.id)
        name = user.name
        email = user.email
    }
}
