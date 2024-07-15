import Foundation

public struct JWT: Equatable {
    public let token: String
    public let expiryDate: Date
}

#if DEBUG
    extension JWT {
        public static func test(
            token: String = "token",
            expiryDate: Date = Date()
        ) -> JWT {
            .init(
                token: token,
                expiryDate: expiryDate
            )
        }
    }
#endif
