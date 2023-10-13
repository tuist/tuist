#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudProjectDeleteServicing {
        func run(
            projectName: String,
            organizationName: String?,
            directory: String?
        ) async throws
    }

    final class CloudProjectDeleteService: CloudProjectDeleteServicing {
        private let deleteProjectService: DeleteProjectServicing
        private let getProjectService: GetProjectServicing
        private let credentialsStore: CredentialsStoring
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading
        
        init(
            deleteProjectService: DeleteProjectServicing = DeleteProjectService(),
            getProjectService: GetProjectServicing = GetProjectService(),
            credentialsStore: CredentialsStoring = CredentialsStore(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.deleteProjectService = deleteProjectService
            self.getProjectService = getProjectService
            self.credentialsStore = credentialsStore
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            projectName: String,
            organizationName: String?,
            directory: String?
        ) async throws {
            let directoryPath: AbsolutePath
            if let directory {
                directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
            } else {
                directoryPath = FileHandler.shared.currentPath
            }
            let config = try self.configLoader.loadConfig(path: directoryPath)
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

            let accountName: String
            if let organizationName {
                accountName = organizationName
            } else {
                let credentials = try credentialsStore.get(serverURL: cloudURL)
                accountName = credentials.account
            }

            let project = try await getProjectService.getProject(
                accountName: accountName,
                projectName: projectName,
                serverURL: cloudURL
            )

            try await deleteProjectService.deleteProject(
                projectId: project.id,
                serverURL: cloudURL
            )

            logger.info("Successfully deleted the \(project.fullName) project.")
        }
    }
#endif
