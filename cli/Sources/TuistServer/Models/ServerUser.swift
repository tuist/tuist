import Foundation

/// Server user
public struct ServerUser: Codable {
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

    init(_ user: Components.Schemas.User) {
        id = Int(user.id)
        name = user.name
        email = user.email
    }

    #if MOCKING
        public static func test(
            id: Int = 0,
            name: String = "test",
            email: String = "test@email.io"
        ) -> Self {
            .init(
                id: id,
                name: name,
                email: email
            )
        }
    #endif
}
