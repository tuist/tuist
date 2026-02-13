import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol OrganizationRemoveMemberServicing {
    func run(
        organizationName: String,
        username: String,
        directory: String?
    ) async throws
}

struct OrganizationRemoveMemberService: OrganizationRemoveMemberServicing {
    private let removeOrganizationMemberService: RemoveOrganizationMemberServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        removeOrganizationMemberService: RemoveOrganizationMemberServicing =
            RemoveOrganizationMemberService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.removeOrganizationMemberService = removeOrganizationMemberService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        username: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await removeOrganizationMemberService.removeOrganizationMember(
            organizationName: organizationName,
            username: username,
            serverURL: serverURL
        )

        Logger.current
            .info(
                "The member \(username) was successfully removed from the \(organizationName) organization."
            )
    }
}
