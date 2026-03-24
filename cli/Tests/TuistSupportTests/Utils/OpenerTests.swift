import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistOpener
@testable import TuistSupport
@testable import TuistTesting

struct OpeningErrorTests {
    @Test
    func test_type() {
        let path = try! AbsolutePath(validating: "/test")
        #expect(OpeningError.notFound(path).type == .bug)
    }

    @Test
    func test_description() {
        let path = try! AbsolutePath(validating: "/test")
        #expect(OpeningError.notFound(path).description == "Couldn't open file at path /test")
    }
}

struct OpenerTests {
    private let system = MockSystem()
    let subject: Opener
    init() {
        subject = Opener()
    }

    @Test(.inTemporaryDirectory)
    func open_when_path_doesnt_exist() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryPath.appending(component: "tool")

        await #expect(throws: OpeningError.notFound(path)) { try await subject.open(path: path) }
    }

    @Test(.inTemporaryDirectory)
    func open_when_wait_is_false() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryPath.appending(component: "tool")
        try FileHandler.shared.touch(path)
        system.succeedCommand(["/usr/bin/open", path.pathString])
        try await subject.open(path: path)
    }
}
