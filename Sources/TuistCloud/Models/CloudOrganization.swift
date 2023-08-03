import Foundation

/// Cloud organization
public struct CloudOrganization: Codable {
    public let id: Int
    public let name: String

    public init(
        id: Int,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

extension CloudOrganization {
    init(_ organization: Components.Schemas.Organization) {
        id = Int(organization.id)
        name = organization.name
    }
}
