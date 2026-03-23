import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import FileSystemTesting
import Testing

@testable import TuistCacheEE

struct ArtifactSignerTests {
    let subject: ArtifactSigner
    init() {
        subject = ArtifactSigner()
    }


    @Test(.inTemporaryDirectory)
    func test_crud() throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let filePath = temporaryDirectory.appending(component: "Test")
        try "Test".write(to: filePath.url, atomically: true, encoding: .utf8)

        // When
        #expect(!try subject.isValid(filePath))
        try subject.sign(filePath)
        #expect(try subject.isValid(filePath))
        try subject.removeSignature(filePath)
        #expect(!try subject.isValid(filePath))
    }
}
