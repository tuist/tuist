import Foundation
import TSCBasic
import TuistCloud
import TuistSupport
import TuistLoader

protocol CloudProjectCreateServicing {
    func run(
        name: String,
        serverURL: String?
    ) async throws
}

final class CloudProjectCreateService: CloudProjectCreateServicing {
    private let createProjectService: CreateProjectNextServicing
    private let configLoader: ConfigLoading
    
    init(
        createProjectService: CreateProjectNextServicing = CreateProjectNextService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createProjectService = createProjectService
        self.configLoader = configLoader
    }
    
    func run(
        name: String,
        serverURL: String?
    ) async throws {
        if try !configLoader.loadConfig(path: FileHandler.shared.currentPath).beta.contains(.cloudNext) {
            logger.warning("Enable this feature by adding cloudNext in your Config.swift")
            return
        }
        try await createProjectService.createProject(
            name: name,
            // TODO: Allow specifying org name
            organizationName: nil,
            // TODO: Handle invalid URL
            serverURL: URL(string: serverURL ?? Constants.tuistCloudNextURL)!
        )
        
        logger.info("Project was successfully created.")
    }
}
