import Foundation

public enum SSOOrganization: Codable, Equatable {
    case google(String)
    case okta(String)
}
