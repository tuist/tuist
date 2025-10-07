import FileSystem
import Mockable
import Path
import TuistTesting
import XCTest

@testable import TuistCore

final class XCFrameworkSignatureProviderIntegrationTests: TuistUnitTestCase {
    private var subject: XCFrameworkSignatureProvider!
    private var codesignController: MockCodesignControlling!
    private var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        codesignController = MockCodesignControlling()

        subject = XCFrameworkSignatureProvider(
            fileSystem: FileSystem(),
            codesignController: codesignController
        )

        path = fixturePath(
            path: try! RelativePath(validating: "MyFramework.xcframework")
        )
    }

    override func tearDown() {
        subject = nil
        codesignController = nil
        path = nil
        super.tearDown()
    }

    func test_signature_unsigned() async throws {
        // Given
        given(codesignController)
            .signature(of: .value(path))
            .willReturn(nil)

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .unsigned)
    }

    func test_signature_appleSigned() async throws {
        // Given
        let codesignOutput = """
        Identifier=SignedXCFramework
        Authority=Developer ID Application: Tuist GmbH (U6LC622NKF)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=U6LC622NKF
        """

        given(codesignController)
            .signature(of: .value(path))
            .willReturn(codesignOutput)

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .signedWithAppleCertificate(teamIdentifier: "U6LC622NKF", teamName: "Tuist GmbH"))
    }

    func test_signature_appleSignedNoTeamIdInAuthority() async throws {
        // Given
        let codesignOutput = """
        Identifier=SignedXCFramework
        Authority=iPhone Distribution: Tuist GmbH
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=U6LC622NKF
        """

        given(codesignController)
            .signature(of: .value(path))
            .willReturn(codesignOutput)

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .signedWithAppleCertificate(teamIdentifier: "U6LC622NKF", teamName: "Tuist GmbH"))
    }

    func test_signature_selfSigned() async throws {
        // Given
        let codesign0FixturePath = fixturePath(
            path: try RelativePath(validating: "SelfSignedXCFrameworkCodesign0/codesign0")
        )
        let mockFileSystem = SelfSignedXCFrameworkMockFileSystem(codesign0FixturesPath: codesign0FixturePath)

        let subject = XCFrameworkSignatureProvider(
            fileSystem: mockFileSystem,
            codesignController: codesignController
        )

        let selfSignedPath = fixturePath(
            path: try RelativePath(validating: "SelfSignedXCFramework.xcframework")
        )

        given(codesignController)
            .signature(of: .value(selfSignedPath))
            .willReturn("Authority=Tuist Test Example")

        given(codesignController)
            .extractSignature(of: .value(selfSignedPath), into: .any)
            .willProduce { _, _ in
                mockFileSystem.certificateExtractionCallDone()
            }

        // When
        let result = try await subject.signature(of: selfSignedPath)

        // Then
        let expectedFingerprint = "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
        XCTAssertEqual(result, .selfSigned(fingerprint: expectedFingerprint))
    }
}

/// Mock implementation of `FileSysteming` designated specifically to test providing signature of self signed frameworks.
/// The methods that are involved in returning the codesign output are mocked, the rest throw an error.
private class SelfSignedXCFrameworkMockFileSystem: FileSysteming {
    func contentsOfDirectory(_: Path.AbsolutePath) async throws -> [Path.AbsolutePath] {
        return []
    }

    /// Temporary path to be returned by the mock when running on temporary files.
    private let tempFilePathString: String

    /// Path to the self signed framework codesign0 file inside the test fixtures.
    private let codesign0FixturesPath: AbsolutePath

    /// Should change to `true` when the certificates are extracted.
    /// Used for making sure the codesign0 file is attempted to be read from only after its creation.
    private var certificateExtractionCalled: Bool

    init(codesign0FixturesPath: AbsolutePath) {
        self.codesign0FixturesPath = codesign0FixturesPath
        tempFilePathString = "/tmp/xcframework-signature-test/\(UUID().uuidString)"
        certificateExtractionCalled = false
    }

    func certificateExtractionCallDone() {
        certificateExtractionCalled = true
    }

    func runInTemporaryDirectory<T>(
        prefix _: String,
        _ action: @Sendable (Path.AbsolutePath) async throws -> T
    ) async throws -> T {
        let tempPath = try AbsolutePath(validating: tempFilePathString)
        return try await action(tempPath)
    }

    func exists(_ path: Path.AbsolutePath) async throws -> Bool {
        return try certificateExtractionCalled && path == AbsolutePath(validating: tempFilePathString)
            .appending(component: "codesign0")
    }

    func exists(_ path: Path.AbsolutePath, isDirectory: Bool) async throws -> Bool {
        guard !isDirectory else { throw unexpectedCallError() }
        return try await exists(path)
    }

    func readFile(at path: Path.AbsolutePath) async throws -> Data {
        guard try path == AbsolutePath(validating: tempFilePathString).appending(component: "codesign0") else {
            throw unexpectedCallError()
        }

        return try Data(contentsOf: URL(fileURLWithPath: codesign0FixturesPath.pathString))
    }

    func unexpectedCallError() -> Error {
        return NSError(domain: "Unexpected call to mocked method", code: 1, userInfo: nil)
    }

    func touch(_: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func remove(_: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func makeTemporaryDirectory(prefix _: String) async throws -> Path.AbsolutePath { throw unexpectedCallError() }
    func move(from _: Path.AbsolutePath, to _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func move(from _: Path.AbsolutePath, to _: Path.AbsolutePath, options _: [MoveOptions]) async throws {
        throw unexpectedCallError()
    }

    func makeDirectory(at _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func makeDirectory(at _: Path.AbsolutePath, options _: [MakeDirectoryOptions]) async throws { throw unexpectedCallError() }
    func readTextFile(at _: Path.AbsolutePath) async throws -> String { throw unexpectedCallError() }
    func readTextFile(at _: Path.AbsolutePath, encoding _: String.Encoding) async throws -> String { throw unexpectedCallError() }
    func readPlistFile<T>(at _: Path.AbsolutePath) async throws -> T where T: Decodable { throw unexpectedCallError() }
    func readPlistFile<T>(at _: Path.AbsolutePath, decoder _: PropertyListDecoder) async throws -> T
        where T: Decodable { throw unexpectedCallError() }
    func readJSONFile<T>(at _: Path.AbsolutePath) async throws -> T where T: Decodable { throw unexpectedCallError() }
    func readJSONFile<T>(at _: Path.AbsolutePath, decoder _: JSONDecoder) async throws -> T
        where T: Decodable { throw unexpectedCallError() }
    func fileSizeInBytes(at _: Path.AbsolutePath) async throws -> Int64? { throw unexpectedCallError() }
    func replace(_: Path.AbsolutePath, with _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func copy(_: Path.AbsolutePath, to _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func locateTraversingUp(
        from _: Path.AbsolutePath,
        relativePath _: RelativePath
    ) async throws -> AbsolutePath? { throw unexpectedCallError() }
    func createSymbolicLink(from _: Path.AbsolutePath, to _: AbsolutePath) async throws { throw unexpectedCallError() }
    func createSymbolicLink(from _: Path.AbsolutePath, to _: RelativePath) async throws { throw unexpectedCallError() }
    func resolveSymbolicLink(_: Path.AbsolutePath) async throws -> Path.AbsolutePath { throw unexpectedCallError() }
    func zipFileOrDirectoryContent(at _: Path.AbsolutePath, to _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func unzip(_: Path.AbsolutePath, to _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func glob(
        directory _: Path.AbsolutePath,
        include _: [String]
    ) throws -> AnyThrowingAsyncSequenceable<AbsolutePath> { throw unexpectedCallError() }
    func currentWorkingDirectory() async throws -> Path.AbsolutePath { throw unexpectedCallError() }
    func writeText(
        _: String,
        at _: Path.AbsolutePath,
        encoding _: String.Encoding,
        options _: Set<WriteTextOptions>
    ) async throws { throw unexpectedCallError() }
    func writeAsPlist(
        _: some Encodable,
        at _: Path.AbsolutePath,
        encoder _: PropertyListEncoder,
        options _: Set<WritePlistOptions>
    ) async throws { throw unexpectedCallError() }
    func writeAsJSON(
        _: some Encodable,
        at _: Path.AbsolutePath,
        encoder _: JSONEncoder,
        options _: Set<WriteJSONOptions>
    ) async throws { throw unexpectedCallError() }
    func writeText(_: String, at _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func writeText(_: String, at _: Path.AbsolutePath, encoding _: String.Encoding) async throws { throw unexpectedCallError() }
    func writeAsPlist(_: some Encodable, at _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func writeAsPlist(_: some Encodable, at _: Path.AbsolutePath, encoder _: PropertyListEncoder) async throws {
        throw unexpectedCallError()
    }

    func writeAsJSON(_: some Encodable, at _: Path.AbsolutePath) async throws { throw unexpectedCallError() }
    func writeAsJSON(_: some Encodable, at _: Path.AbsolutePath, encoder _: JSONEncoder) async throws {
        throw unexpectedCallError()
    }

    func fileMetadata(at _: AbsolutePath) async throws -> FileMetadata? { throw unexpectedCallError() }
}
