#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudProjectCreateServicing {
        func run(
            name: String,
            organization: String?,
            directory: String?
        ) async throws
    }

    final class CloudProjectCreateService: CloudProjectCreateServicing {
        private let createProjectService: CreateProjectServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            createProjectService: CreateProjectServicing = CreateProjectService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.createProjectService = createProjectService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            name: String,
            organization: String?,
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

            let project = try await createProjectService.createProject(
                name: name,
                organization: organization,
                serverURL: cloudURL
            )

            logger.info("Tuist Cloud project \(project.fullName) was successfully created 🎉")
        }
    }
#endif
