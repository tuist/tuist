import Foundation

/// Server organization
public struct ServerOrganization: Codable {
    public enum Plan: String, Codable {
        case air
        case pro
        case enterprise
        case none

        public init(_ organization: Components.Schemas.Organization.planPayload) {
            switch organization {
            case .air:
                self = .air
            case .pro:
                self = .pro
            case .enterprise:
                self = .enterprise
            case .none, .undocumented:
                self = .none
            }
        }
    }

    public struct Member: Codable {
        public enum Role: Codable, RawRepresentable {
            case user, admin

            public init?(rawValue: String) {
                switch rawValue {
                case "user":
                    self = .user
                case "admin":
                    self = .admin
                default:
                    self = .user
                }
            }

            public var rawValue: String {
                switch self {
                case .user:
                    return "user"
                case .admin:
                    return "admin"
                }
            }
        }

        public let id: Int
        public let name: String
        public let email: String
        public let role: Role

        public init(
            id: Int,
            name: String,
            email: String,
            role: Role
        ) {
            self.id = id
            self.name = name
            self.email = email
            self.role = role
        }
    }

    public let id: Int
    public let name: String
    public let plan: Plan
    public let members: [Member]
    public let invitations: [ServerInvitation]
    public let ssoOrganization: SSOOrganization?

    public init(
        id: Int,
        name: String,
        plan: Plan,
        members: [Member],
        invitations: [ServerInvitation],
        ssoOrganization: SSOOrganization?
    ) {
        self.id = id
        self.name = name
        self.plan = plan
        self.members = members
        self.invitations = invitations
        self.ssoOrganization = ssoOrganization
    }
}

extension ServerOrganization {
    init(_ organization: Components.Schemas.Organization) {
        id = Int(organization.id)
        name = organization.name
        plan = Plan(organization.plan)
        members = organization.members.map(Member.init)
        invitations = organization.invitations.map(ServerInvitation.init)
        if let ssoProvider = organization.sso_provider,
           let ssoOrganizationId = organization.sso_organization_id
        {
            switch ssoProvider {
            case .google:
                ssoOrganization = .google(ssoOrganizationId)
            case .undocumented:
                ssoOrganization = nil
            }
        } else {
            ssoOrganization = nil
        }
    }
}

extension ServerOrganization.Member {
    init(_ organizationMember: Components.Schemas.OrganizationMember) {
        id = Int(organizationMember.id)
        name = organizationMember.name
        email = organizationMember.email
        switch organizationMember.role {
        case .admin:
            role = .admin
        case .user, .undocumented:
            role = .user
        }
    }
}

#if MOCKING
    extension ServerOrganization {
        public static func test(
            id: Int = 0,
            name: String = "test",
            plan: Plan = .air,
            members: [Member] = [],
            invitations: [ServerInvitation] = [],
            ssoOrganization: SSOOrganization? = nil
        ) -> Self {
            .init(
                id: id,
                name: name,
                plan: plan,
                members: members,
                invitations: invitations,
                ssoOrganization: ssoOrganization
            )
        }
    }

    extension ServerOrganization.Member {
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
#endif
