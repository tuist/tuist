import Command
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting

@testable import TuistCore
@testable import TuistTesting

@Suite struct CodesignControllerTests {
    private let commandRunner = MockCommandRunning()
    private let subject: CodesignController
    private let unsignedPath: AbsolutePath
    private let signedPath: AbsolutePath

    init() {
        subject = CodesignController(commandRunner: commandRunner)
        unsignedPath = SwiftTestingHelper.fixturePath(
            path: try! RelativePath(validating: "MyFramework.xcframework")
        )
        signedPath = SwiftTestingHelper.fixturePath(
            path: try! RelativePath(validating: "SignedXCFramework.xcframework")
        )
    }

    @Test func signature_returnsSignature() async throws {
        let expected = "mockSignature"
        given(commandRunner)
            .run(
                arguments: .value(["/usr/bin/codesign", "-dvv", signedPath.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(expected.utf8)))
                    continuation.finish()
                }
            )

        let result = try await subject.signature(of: signedPath)
        #expect(result == expected)
    }

    @Test func signature_returnsNilIfUnsigned() async throws {
        let stderr = "code object is not signed at all"
        given(commandRunner)
            .run(
                arguments: .value(["/usr/bin/codesign", "-dvv", unsignedPath.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(stderr.utf8)))
                    continuation.finish(throwing: CommandError.terminated(1, stderr: stderr))
                }
            )

        let result = try await subject.signature(of: unsignedPath)
        #expect(result == nil)
    }

    @Test func signature_throwsForOtherErrors() async throws {
        let stderr = "some error"
        let expectedCode: Int32 = 1
        given(commandRunner)
            .run(
                arguments: .value(["/usr/bin/codesign", "-dvv", unsignedPath.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(stderr.utf8)))
                    continuation.finish(throwing: CommandError.terminated(expectedCode, stderr: stderr))
                }
            )

        await #expect {
            try await subject.signature(of: unsignedPath)
        } throws: { error in
            if let terminated = error as? CommandError,
               case let .terminated(actualCode, actualStderr) = terminated
            {
                return actualCode == 1 && actualStderr == stderr
            }
            return false
        }
    }

    @Test func extractSignature_extractionSucceeds() async throws {
        let outputDir = try TemporaryDirectory(removeTreeOnDeinit: true).path
        given(commandRunner)
            .run(
                arguments: .value([
                    "/usr/bin/codesign",
                    "-d",
                    "--extract-certificates",
                    signedPath.pathString,
                ]),
                environment: .any,
                workingDirectory: .value(outputDir)
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            )

        try await subject.extractSignature(of: signedPath, into: outputDir)
    }

    @Test func extractSignature_extractionFails() async throws {
        let outputDir = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let stderr = "some error"
        let error = CommandError.terminated(1, stderr: stderr)

        given(commandRunner)
            .run(
                arguments: .value([
                    "/usr/bin/codesign",
                    "-d",
                    "--extract-certificates",
                    unsignedPath.pathString,
                ]),
                environment: .any,
                workingDirectory: .value(outputDir)
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: error)
                }
            )

        await #expect {
            try await subject.extractSignature(of: unsignedPath, into: outputDir)
        } throws: { error in
            if let terminated = error as? CommandError,
               case let .terminated(actualCode, actualStderr) = terminated
            {
                return actualCode == 1 && actualStderr == stderr
            }
            return false
        }
    }
}
