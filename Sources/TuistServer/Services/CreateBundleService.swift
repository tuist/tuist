import Foundation
import Mockable
import OpenAPIURLSession
import Path
import Rosalind
import TuistSupport

@Mockable
public protocol CreateBundleServicing {
    func createBundle(
        fullHandle: String,
        serverURL: URL,
        artifact: RosalindReport
    ) async throws -> ServerBundle
}

enum CreateBundleServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The build could not be uploaded due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public final class CreateBundleService: CreateBundleServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func createBundle(
        fullHandle: String,
        serverURL: URL,
        artifact: RosalindReport
    ) async throws -> ServerBundle {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.createBundle(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        bundle: .init(
                            artifacts: [
                                .init(artifact),
                            ],
                            name: try RelativePath(validating: artifact.path).basenameWithoutExt
                        )
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(bundle):
                return ServerBundle(bundle)!
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateBundleServiceError.unknownError(statusCode)
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                fatalError()
            }
        case .unprocessableContent:
            fatalError()
        }
    }
}

public struct ServerBundle {
    public let url: URL

    init?(_ bundle: Components.Schemas.Bundle) {
        guard let url = URL(string: bundle.url)
        else { return nil }
        self.url = url
    }
}

extension Components.Schemas.BundleArtifact {
    init(_ report: RosalindReport) {
        let artifactType: Components.Schemas.BundleArtifact.artifact_typePayload = switch report.artifactType {
        case .app: fatalError()
        case .directory: .directory
        case .file: .file
        case .font: .font
        case .binary: .binary
        }
        self.init(
            artifact_type: artifactType,
            children: report.children.map {
                $0.map { Self($0) }
            },
            path: report.path,
            shasum: report.shasum,
            size: report.size
        )
    }
}
