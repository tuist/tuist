import TuistCloud

extension CloudUser {
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
}
