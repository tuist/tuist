import Foundation
import TSCBasic
import TuistServer
import TuistLoader
import TuistSupport

protocol CloudProjectTokenServicing {
    func run(
        projectName: String,
        organizationName: String,
        directory: String?
    ) async throws
}

final class CloudProjectTokenService: CloudProjectTokenServicing {
    private let getProjectService: GetProjectServicing
    private let credentialsStore: CloudCredentialsStoring
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        getProjectService: GetProjectServicing = GetProjectService(),
        credentialsStore: CloudCredentialsStoring = CloudCredentialsStore(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getProjectService = getProjectService
        self.credentialsStore = credentialsStore
        self.cloudURLService = cloudURLService
        self.configLoader = configLoader
    }

    func run(
        projectName: String,
        organizationName: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

        let accountName: String = organizationName

        let project = try await getProjectService.getProject(
            accountName: accountName,
            projectName: projectName,
            serverURL: cloudURL
        )

        logger.info(.init(stringLiteral: project.token))
    }
}
