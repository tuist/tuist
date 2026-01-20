import Foundation
import Mockable
import Path
import TuistServer
import TuistSupport

@Mockable
public protocol MultipartModuleCacheUploadServicing: Sendable {
    func uploadArtifact(
        artifactPath: AbsolutePath,
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum MultipartModuleCacheUploadServiceError: LocalizedError {
    case fileNotFound(AbsolutePath)
    case fileReadError(AbsolutePath, Error)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "Artifact file not found at \(path.pathString)"
        case let .fileReadError(path, error):
            return "Failed to read artifact file at \(path.pathString): \(error.localizedDescription)"
        }
    }
}

public struct MultipartModuleCacheUploadService: MultipartModuleCacheUploadServicing {
    private let startUploadService: StartModuleCacheMultipartUploadServicing
    private let uploadPartService: UploadModuleCachePartServicing
    private let completeUploadService: CompleteModuleCacheMultipartUploadServicing

    private static let partSize = 10 * 1024 * 1024

    public init(
        startUploadService: StartModuleCacheMultipartUploadServicing = StartModuleCacheMultipartUploadService(),
        uploadPartService: UploadModuleCachePartServicing = UploadModuleCachePartService(),
        completeUploadService: CompleteModuleCacheMultipartUploadServicing = CompleteModuleCacheMultipartUploadService()
    ) {
        self.startUploadService = startUploadService
        self.uploadPartService = uploadPartService
        self.completeUploadService = completeUploadService
    }

    public func uploadArtifact(
        artifactPath: AbsolutePath,
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        guard let uploadId = try await startUploadService.startUpload(
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            hash: hash,
            name: name,
            cacheCategory: cacheCategory,
            serverURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        ) else {
            return
        }

        guard FileManager.default.fileExists(atPath: artifactPath.pathString) else {
            throw MultipartModuleCacheUploadServiceError.fileNotFound(artifactPath)
        }

        guard let inputStream = InputStream(fileAtPath: artifactPath.pathString) else {
            throw MultipartModuleCacheUploadServiceError.fileNotFound(artifactPath)
        }

        inputStream.open()
        defer { inputStream.close() }

        var partNumber = 1
        var uploadedParts: [Int] = []
        var buffer = [UInt8](repeating: 0, count: Self.partSize)

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: Self.partSize)

            if bytesRead < 0 {
                if let error = inputStream.streamError {
                    throw MultipartModuleCacheUploadServiceError.fileReadError(artifactPath, error)
                }
                break
            }

            if bytesRead == 0 {
                break
            }

            let partData = Data(bytes: buffer, count: bytesRead)

            try await uploadPartService.uploadPart(
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                uploadId: uploadId,
                partNumber: partNumber,
                data: partData,
                serverURL: serverURL,
                authenticationURL: authenticationURL,
                serverAuthenticationController: serverAuthenticationController
            )

            uploadedParts.append(partNumber)
            partNumber += 1
        }

        try await completeUploadService.completeUpload(
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            uploadId: uploadId,
            parts: uploadedParts,
            serverURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )
    }
}
