import Foundation

public struct ServerProjectToken {
    public let id: String
    public let insertedAt: Date

    init(_ projectToken: Components.Schemas.ProjectToken) {
        id = projectToken.id
        insertedAt = projectToken.inserted_at
    }

    #if DEBUG
        public static func test(
            id: String = "project-token-id",
            insertedAt: Date = Date()
        ) -> Self {
            self.init(
                id: id,
                insertedAt: insertedAt
            )
        }
    #endif
}
