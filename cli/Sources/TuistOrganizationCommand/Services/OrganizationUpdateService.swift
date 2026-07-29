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
        enrollmentPolicy: SSOEnrollmentPolicy?,
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
        enrollmentPolicy: SSOEnrollmentPolicy?,
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
        let automaticEnrollment = enrollmentPolicy.map { $0 == .automatic }

        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: serverURL,
            ssoOrganization: ssoOrganization,
            ssoAutomaticEnrollment: automaticEnrollment
        )

        if automaticEnrollment == true {
            Logger.current.info(
                "\(organizationName) now uses \(provider.rawValue.capitalized) SSO with \(organizationId). Authenticated users will automatically have access to the \(organizationName) projects."
            )
        } else if automaticEnrollment == false {
            Logger.current.info(
                "\(organizationName) now uses \(provider.rawValue.capitalized) SSO with \(organizationId). Users need an invitation to access the \(organizationName) projects."
            )
        } else {
            Logger.current.info(
                "\(organizationName) now uses \(provider.rawValue.capitalized) SSO with \(organizationId). No enrollment policy was specified."
            )
        }
    }
}
