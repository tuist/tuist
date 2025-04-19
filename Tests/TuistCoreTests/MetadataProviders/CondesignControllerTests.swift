import Command
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupportTesting
import XCTest

@testable import TuistCore

final class CodesignControllerTests: TuistUnitTestCase {
    private var subject: CodesignController!
    private var commandRunner: MockCommandRunning!
    private var unsignedPath: AbsolutePath!
    private var signedPath: AbsolutePath!

    override func setUp() {
        super.setUp()
        commandRunner = MockCommandRunning()
        subject = CodesignController(commandRunner: commandRunner)

        unsignedPath = fixturePath(
            path: try! RelativePath(validating: "MyFramework.xcframework")
        )
        signedPath = fixturePath(
            path: try! RelativePath(validating: "SignedXCFramework.xcframework")
        )
    }

    override func tearDown() {
        commandRunner = nil
        subject = nil
        super.tearDown()
    }

    func test_codesignSignature_returnsSignature() async throws {
        // Given
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

        // When
        let result = try await subject.codesignSignature(of: signedPath)

        // Then
        XCTAssertEqual(result, expected)
    }

    func test_codesignSignature_returnsNilIfUnsigned() async throws {
        // Given
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

        // When
        let result = try await subject.codesignSignature(of: unsignedPath)

        // Then
        XCTAssertNil(result)
    }

    func test_codesignSignature_throwsForOtherErrors() async throws {
        // Given
        let stderr = "some error"
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

        // When / Then
        await XCTAssertThrowsCommandErrorTerminated(
            try await subject.codesignSignature(of: unsignedPath),
            expectedCode: 1,
            expectedStderr: stderr
        )
    }

    func test_codesignExtractSignature_extractionSucceeds() async throws {
        // Given
        let outputDir = try temporaryPath()
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

        // When / Then
        try await subject.codesignExtractSignature(of: signedPath, into: outputDir)
    }

    func test_codesignExtractSignature_extractionFails() async throws {
        // Given
        let outputDir = try temporaryPath()
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

        // When / Then
        await XCTAssertThrowsCommandErrorTerminated(
            try await subject.codesignExtractSignature(of: unsignedPath, into: outputDir),
            expectedCode: 1,
            expectedStderr: stderr
        )
    }
}

func XCTAssertThrowsCommandErrorTerminated(
    _ expression: @autoclosure () async throws -> some Any,
    expectedCode: Int32,
    expectedStderr: String,
    file: StaticString = #file,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected CommandError.terminated to be thrown", file: file, line: line)
    } catch let CommandError.terminated(code, stderr) {
        XCTAssertEqual(code, expectedCode, file: file, line: line)
        XCTAssertEqual(stderr, expectedStderr, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
