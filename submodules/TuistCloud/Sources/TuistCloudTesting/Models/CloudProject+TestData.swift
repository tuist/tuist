import TuistCloud

extension CloudProject {
    public static func test(
        id: Int = 0,
        fullName: String = "test/test",
        token: String = "token"
    ) -> Self {
        .init(
            id: id,
            fullName: fullName,
            token: token
        )
    }
}
