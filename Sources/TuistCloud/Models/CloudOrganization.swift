import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Cloud organization
public struct CloudOrganization: Codable {
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
    public let members: [Member]
    public let invitations: [CloudInvitation]

    public init(
        id: Int,
        name: String,
        members: [Member],
        invitations: [CloudInvitation]
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.invitations = invitations
    }
}

extension CloudOrganization {
    init(_ organization: Components.Schemas.Organization) {
        id = Int(organization.id)
        name = organization.name
        members = organization.members.map(Member.init)
        invitations = organization.invitations.map(CloudInvitation.init)
    }
}

extension CloudOrganization.Member {
    init(_ organizationMember: Components.Schemas.OrganizationMember) {
        id = Int(organizationMember.id)
        name = organizationMember.name
        email = organizationMember.email
        switch organizationMember.role {
        case .admin:
            role = .admin
        case .user:
            role = .user
        }
    }
}
