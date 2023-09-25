import TuistCloud

extension CloudOrganization {
    public static func test(
        id: Int = 0,
        name: String = "test",
        plan: Plan = .team,
        members: [Member] = [],
        invitations: [CloudInvitation] = []
    ) -> Self {
        .init(
            id: id,
            name: name,
            plan: plan,
            members: members,
            invitations: invitations
        )
    }
}

extension CloudOrganization.Member {
    public static func test(
        id: Int = 0,
        name: String = "test",
        email: String = "test@email.io",
        role: Role = .user
    ) -> Self {
        .init(
            id: id,
            name: name,
            email: email,
            role: role
        )
    }
}
