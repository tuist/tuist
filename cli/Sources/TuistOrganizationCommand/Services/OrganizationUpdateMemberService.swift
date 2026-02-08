import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

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
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationMemberService: UpdateOrganizationMemberServicing =
            UpdateOrganizationMemberService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationMemberService = updateOrganizationMemberService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        username: String,
        role: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let member = try await updateOrganizationMemberService.updateOrganizationMember(
            organizationName: organizationName,
            username: username,
            role: ServerOrganization.Member.Role(rawValue: role) ?? .user,
            serverURL: serverURL
        )

        Logger.current.info(
            "The member \(username) role was successfully updated to \(member.role.rawValue)."
        )
    }
}
