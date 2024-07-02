import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudProjectTokenServicing {
    func run(
        fullHandle: String,
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
        fullHandle: String,
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

        let project = try await getProjectService.getProject(
            fullHandle: fullHandle,
            serverURL: cloudURL
        )

        logger.info(.init(stringLiteral: project.token))
    }
}
