import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationRemoveMemberServicing {
    func run(
        organizationName: String,
        username: String,
        directory: String?
    ) async throws
}

final class OrganizationRemoveMemberService: OrganizationRemoveMemberServicing {
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
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
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
