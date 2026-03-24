import FileSystem
import FileSystemTesting
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistCacheEE

struct ArtifactSignerTests {
    let subject: ArtifactSigner
    init() {
        subject = ArtifactSigner()
    }

    @Test(.inTemporaryDirectory)
    func crud() throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let filePath = temporaryDirectory.appending(component: "Test")
        try "Test".write(to: filePath.url, atomically: true, encoding: .utf8)

        // When
        #expect(try subject.isValid(filePath) == false)
        try subject.sign(filePath)
        #expect(try subject.isValid(filePath))
        try subject.removeSignature(filePath)
        #expect(try subject.isValid(filePath) == false)
    }
}
