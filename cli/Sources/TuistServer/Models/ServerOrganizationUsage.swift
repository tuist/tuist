import Foundation

/// Server organization usage
public struct ServerOrganizationUsage: Codable {
    public init() {}

    init(_: Components.Schemas.OrganizationUsage) {}

    #if DEBUG
        public static func test() -> Self {
            .init()
        }
    #endif
}
