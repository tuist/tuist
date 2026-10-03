import CryptoKit
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Synchronization
import Testing
import TuistServer

@testable import TuistCache

struct MultipartModuleCacheUploadServiceTests {
    private let startUploadService = MockStartModuleCacheMultipartUploadServicing()
    private let uploadPartService = MockUploadModuleCachePartServicing()
    private let completeUploadService = MockCompleteModuleCacheMultipartUploadServicing()
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let serverURL = URL(string: "https://cache.tuist.dev")!

    private var subject: MultipartModuleCacheUploadService {
        MultipartModuleCacheUploadService(
            startUploadService: startUploadService,
            uploadPartService: uploadPartService,
            completeUploadService: completeUploadService
        )
    }

    private final class Attempts: Sendable {
        private let count = Mutex(0)

        func next() -> Int {
            count.withLock { value in
                value += 1
                return value
            }
        }
    }

    private func artifact(_ data: Data) throws -> AbsolutePath {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "Module.aar")
        try data.write(to: path.url)
        return path
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func upload(_ path: AbsolutePath) async throws {
        try await subject.uploadArtifact(
            artifactPath: path,
            accountHandle: "tuist",
            projectHandle: "tuist",
            hash: "hash",
            name: "Module.zip",
            cacheCategory: "builds",
            serverURL: serverURL,
            authenticationURL: serverURL,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    private func givenStartReturns(_ uploadIds: [String?]) {
        let attempts = Attempts()
        given(startUploadService)
            .startUpload(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willProduce { _, _, _, _, _, _, _, _ in
                uploadIds[min(attempts.next(), uploadIds.count) - 1]
            }
    }

    private func givenPartsSucceed() {
        given(uploadPartService)
            .uploadPart(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .any,
                partNumber: .any,
                data: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willProduce { _, _, _, _, _, _, _, _ in }
    }

    /// Spans two parts, so the digest has to cover every buffer handed to the
    /// network rather than just the last one.
    @Test(.inTemporaryDirectory) func declares_the_sha256_of_the_bytes_its_parts_carried() async throws {
        let data = Data(repeating: 0xAB, count: 10 * 1024 * 1024 + 7)
        let path = try artifact(data)
        givenStartReturns(["upload"])
        givenPartsSucceed()
        given(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .any,
                parts: .any,
                checksumSHA256: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willProduce { _, _, _, _, _, _, _, _ in }

        try await upload(path)

        verify(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .value("upload"),
                parts: .any,
                checksumSHA256: .value(sha256(data)),
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(1)
    }

    /// The server dropped the session with its parts, and a whole-artifact digest
    /// cannot say which part changed, so the repair is the whole upload again.
    @Test(.inTemporaryDirectory) func uploads_again_from_a_fresh_session_when_the_server_refuses_the_assembly() async throws {
        let path = try artifact(Data("artifact".utf8))
        givenStartReturns(["first", "second"])
        givenPartsSucceed()
        let completions = Attempts()
        given(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .any,
                parts: .any,
                checksumSHA256: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willProduce { _, _, _, _, _, _, _, _ in
                if completions.next() == 1 {
                    throw CompleteModuleCacheMultipartUploadServiceError.checksumMismatch("assembled bytes differ")
                }
            }

        try await upload(path)

        verify(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .value("second"),
                parts: .any,
                checksumSHA256: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(1)
    }

    /// A second refusal means something on this path damages the artifact every
    /// time, so it surfaces instead of looping.
    @Test(.inTemporaryDirectory) func gives_up_after_a_second_refusal() async throws {
        let path = try artifact(Data("artifact".utf8))
        givenStartReturns(["first", "second", "third"])
        givenPartsSucceed()
        given(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .any,
                parts: .any,
                checksumSHA256: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(CompleteModuleCacheMultipartUploadServiceError.checksumMismatch("assembled bytes differ"))

        await #expect(throws: CompleteModuleCacheMultipartUploadServiceError.checksumMismatch("assembled bytes differ")) {
            try await upload(path)
        }

        verify(startUploadService)
            .startUpload(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(2)
    }

    @Test(.inTemporaryDirectory) func does_not_upload_an_artifact_the_server_already_holds() async throws {
        let path = try artifact(Data("artifact".utf8))
        givenStartReturns([nil])

        try await upload(path)

        verify(completeUploadService)
            .completeUpload(
                accountHandle: .any,
                projectHandle: .any,
                uploadId: .any,
                parts: .any,
                checksumSHA256: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(0)
    }
}
