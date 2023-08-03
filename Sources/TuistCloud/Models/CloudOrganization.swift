import Foundation

/// Cloud organization
public struct CloudOrganization {
    public let id: Int
    public let name: String
}

extension CloudOrganization {
    init(_ organization: Components.Schemas.Organization) {
        id = Int(organization.id)
        name = organization.name
    }
}
