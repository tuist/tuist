import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol OrganizationUpdateSSOServicing {
    func run(
        organizationName: String,
        provider: SSOProvider,
        organizationId: String,
        directory: String?
    ) async throws
}

struct OrganizationUpdateSSOService: OrganizationUpdateSSOServicing {
    private let updateOrganizationService: UpdateOrganizationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationService: UpdateOrganizationServicing = UpdateOrganizationService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationService = updateOrganizationService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        provider: SSOProvider,
        organizationId: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)

        let ssoOrganization: SSOOrganization
        switch provider {
        case .google:
            ssoOrganization = .google(organizationId)
        case .okta:
            ssoOrganization = .okta(organizationId)
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: serverURL,
            ssoOrganization: ssoOrganization
        )

        Logger.current
            .info(
                "\(organizationName) now uses \(provider.rawValue.capitalized) SSO with \(organizationId). Users authenticated with the \(organizationId) SSO organization will automatically have access to the \(organizationName) projects."
            )
    }
}
