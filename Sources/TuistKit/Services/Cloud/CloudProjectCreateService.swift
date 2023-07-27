import Foundation
import TSCBasic
import TuistCloud
import TuistSupport

protocol CloudProjectCreateServicing {
    func run(
        name: String,
        serverURL: String?
    ) async throws
}

final class CloudProjectCreateService: CloudProjectCreateServicing {
    private let createProjectService: CreateProjectNextServicing
    
    init(
        createProjectService: CreateProjectNextServicing = CreateProjectNextService()
    ) {
        self.createProjectService = createProjectService
    }
    
    func run(
        name: String,
        serverURL: String?
    ) async throws {
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
