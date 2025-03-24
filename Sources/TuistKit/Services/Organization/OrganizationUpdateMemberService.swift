import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationUpdateMemberServicing {
    func run(
        organizationName: String,
        username: String,
        role: String,
        directory: String?
    ) async throws
}

final class OrganizationUpdateMemberService: OrganizationUpdateMemberServicing {
    private let updateOrganizationMemberService: UpdateOrganizationMemberServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationMemberService: UpdateOrganizationMemberServicing = UpdateOrganizationMemberService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationMemberService = updateOrganizationMemberService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        username: String,
        role: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)

        let serverURL = try serverURLService.url(configServerURL: config.url)
        let member = try await updateOrganizationMemberService.updateOrganizationMember(
            organizationName: organizationName,
            username: username,
            role: ServerOrganization.Member.Role(rawValue: role) ?? .user,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("The member \(username) role was successfully updated to \(member.role.rawValue).")
    }
}
