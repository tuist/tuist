import Foundation

public struct JWT: Equatable {
    public let token: String
    public let expiryDate: Date
    public let email: String?
    public let preferredUsername: String?
}

#if DEBUG
    extension JWT {
        public static func test(
            token: String = "token",
            expiryDate: Date = Date(),
            email: String? = nil,
            preferredUsername: String? = nil
        ) -> JWT {
            .init(
                token: token,
                expiryDate: expiryDate,
                email: email,
                preferredUsername: preferredUsername
            )
        }
    }
#endif
