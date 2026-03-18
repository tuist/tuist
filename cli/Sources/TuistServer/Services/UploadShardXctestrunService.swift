import FileSystem
import Foundation
import Mockable
import Path
import TuistHTTP

@Mockable
public protocol UploadShardXCTestRunServicing {
    func uploadXCTestRun(
        xcTestRunPath: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        planId: String
    ) async throws
}

public enum UploadShardXCTestRunServiceError: LocalizedError, Equatable {
    case uploadFailed(Int)

    public var errorDescription: String? {
        switch self {
        case let .uploadFailed(statusCode):
            return "Failed to upload .xctestrun file (status: \(statusCode))."
        }
    }
}

public struct UploadShardXCTestRunService: UploadShardXCTestRunServicing {
    private let generateUploadURLService: GenerateShardXCTestRunUploadURLServicing
    private let fileSystem: FileSysteming

    public init(
        generateUploadURLService: GenerateShardXCTestRunUploadURLServicing = GenerateShardXCTestRunUploadURLService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.generateUploadURLService = generateUploadURLService
        self.fileSystem = fileSystem
    }

    public func uploadXCTestRun(
        xcTestRunPath: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        planId: String
    ) async throws {
        let uploadURL = try await generateUploadURLService.generateURL(
            fullHandle: fullHandle,
            serverURL: serverURL,
            planId: planId
        )

        let data = try await fileSystem.readFile(at: xcTestRunPath)
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UploadShardXCTestRunServiceError.uploadFailed(statusCode)
        }
    }
}
