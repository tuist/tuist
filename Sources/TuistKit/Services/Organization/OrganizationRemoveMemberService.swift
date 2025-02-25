import Foundation
import Path
import ServiceContextModule
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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        removeOrganizationMemberService: RemoveOrganizationMemberServicing = RemoveOrganizationMemberService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.removeOrganizationMemberService = removeOrganizationMemberService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        username: String,
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

        try await removeOrganizationMemberService.removeOrganizationMember(
            organizationName: organizationName,
            username: username,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?
            .info("The member \(username) was successfully removed from the \(organizationName) organization.")
    }
}
