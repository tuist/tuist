import Foundation

/// Cloud invitation
public struct CloudInvitation: Codable {
    public init(
        id: Int,
        inviteeEmail: String,
        inviter: CloudUser,
        organizationId: Int
    ) {
        self.id = id
        self.inviteeEmail = inviteeEmail
        self.inviter = inviter
        self.organizationId = organizationId
    }

    public let id: Int
    public let inviteeEmail: String
    public let inviter: CloudUser
    public let organizationId: Int
}

extension CloudInvitation {
    init(_ invitation: Components.Schemas.Invitation) {
        id = Int(invitation.id)
        inviteeEmail = invitation.invitee_email
        inviter = CloudUser(invitation.inviter)
        organizationId = Int(invitation.organization_id)
    }
}
