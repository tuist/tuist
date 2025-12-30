import Foundation

/// Server account
public struct ServerAccount: Sendable, Codable, Equatable, Hashable {
    public let id: Int
    public let handle: String

    public init(
        id: Int,
        handle: String
    ) {
        self.id = id
        self.handle = handle
    }
}

extension ServerAccount {
    init(_ account: Components.Schemas.Account) {
        id = Int(account.id)
        handle = account.handle
    }
}

#if MOCKING
    extension ServerAccount {
        public static func test(
            id: Int = 0,
            handle: String = "tuistrocks"
        ) -> Self {
            .init(
                id: id,
                handle: handle
            )
        }
    }
#endif
