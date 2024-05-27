import Foundation
import TSCBasic
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudOrganizationUpdateSSOServicing {
    func run(
        organizationName: String,
        provider: SSOProvider,
        organizationId: String,
        directory: String?
    ) async throws
}

final class CloudOrganizationUpdateSSOService: CloudOrganizationUpdateSSOServicing {
    private let updateOrganizationService: UpdateOrganizationServicing
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationService: UpdateOrganizationServicing = UpdateOrganizationService(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationService = updateOrganizationService
        self.cloudURLService = cloudURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        provider: SSOProvider,
        organizationId: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try configLoader.loadConfig(path: directoryPath)

        let ssoOrganization: SSOOrganization
        switch provider {
        case .google:
            ssoOrganization = .google(organizationId)
        }

        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: cloudURL,
            ssoOrganization: ssoOrganization
        )

        logger
            .info(
                "\(organizationName) now uses \(provider.rawValue.capitalized) SSO with \(organizationId). Users authenticated with the \(organizationId) SSO organization will automatically have access to the \(organizationName) projects."
            )
    }
}
