import Foundation
import TuistCloud
import TuistSupport

protocol CloudInitServicing {
    func createProject(
        name: String,
        owner: String?,
        url: String
    ) async throws
}

enum CloudInitServiceError: FatalError, Equatable {
    case invalidCloudURL(String)

    /// Error description.
    var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL \(url) is invalid."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL:
            return .abort
        }
    }
}

final class CloudInitService: CloudInitServicing {
    private let cloudSessionController: CloudSessionControlling
    private let createProjectService: CreateProjectServicing

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        createProjectService: CreateProjectServicing = CreateProjectService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.createProjectService = createProjectService
    }

    func createProject(
        name: String,
        owner: String?,
        url: String
    ) async throws {
        guard let serverURL = URL(string: url)
        else {
            throw CloudInitServiceError.invalidCloudURL(url)
        }

        let slug = try await createProjectService.createProject(
            name: name,
            organizationName: owner,
            serverURL: serverURL
        )

        logger.info(
            """
            Put the following line into your Tuist/Config.swift (see the docs for more: https://docs.tuist.io/manifests/config/):
            cloud: .cloud(projectId: "\(slug)", url: "\(url)")
            """
        )
    }
}
