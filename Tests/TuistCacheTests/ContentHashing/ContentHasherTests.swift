import Basic
import XCTest
import TuistSupport
@testable import TuistSupportTesting
@testable import TuistCache

final class ContentHasherTests: TuistUnitTestCase {
    private var subject: ContentHasher!
    private var mockFileHandler: MockFileHandling!

    override func setUp() {
        super.setUp()
        mockFileHandler = MockFileHandling()
        subject = ContentHasher(fileHandler: mockFileHandler)
    }

    override func tearDown() {
        subject = nil
        mockFileHandler = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hashstring_foo_returnsItsMd5() throws {
        let hash = try subject.hash("foo")
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8")
    }

    func test_hashstring_bar_returnsItsMd5() throws {
        let hash = try subject.hash("bar")
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2")
    }

    func test_hashstrings_foo_bar_returnsAnotherMd5() throws {
        let hash = try subject.hash(["foo", "bar"])
        XCTAssertEqual(hash, "3858f62230ac3c915f300c664312c63f")
    }

    func test_hashFile_HashesTheExpectedFile() throws {
        let data = Data(repeating: 1, count: 10)
        mockFileHandler.readFileStub = data
        let path = AbsolutePath("/foo")
        let hash = try subject.hash(fileAtPath: path)

        XCTAssertEqual(hash, "484c5624910e6288fad69e572a0637f7")
        XCTAssertEqual(mockFileHandler.readFileSpy, path)
    }

    func test_hashFile_isNotHarcoded() throws {
        let data = Data(repeating: 2, count: 10)
        mockFileHandler.readFileStub = data
        let path = AbsolutePath("/bar")
        let hash = try subject.hash(fileAtPath: path)

        XCTAssertEqual(hash, "0a8d20ca7c979834c6e4d486d648ce1e")
        XCTAssertEqual(mockFileHandler.readFileSpy, path)
    }
}

private final class MockFileHandling: FileHandling {
    var currentPath: AbsolutePath = AbsolutePath("/")

    func replace(_ to: AbsolutePath, with: AbsolutePath) throws {
    }

    func exists(_ path: AbsolutePath) -> Bool {
        return false
    }

    func move(from: AbsolutePath, to: AbsolutePath) throws {
    }

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
    }

    var readFileStub: Data?
    var readFileSpy: AbsolutePath?
    func readFile(_ at: AbsolutePath) throws -> Data {
        readFileSpy = at
        guard let readFileStub = readFileStub else {
            throw NSError(domain: "Mock is missing stub", code: 0, userInfo: nil)
        }
        return readFileStub
    }

    func readTextFile(_ at: AbsolutePath) throws -> String {
        return ""
    }

    func readPlistFile<T>(_ at: AbsolutePath) throws -> T where T : Decodable {
        return try JSONDecoder().decode(T.self, from: Data(capacity: 42))
    }

    func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
    }

    func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
    }

    func locateDirectoryTraversingParents(from: AbsolutePath, path: String) -> AbsolutePath? {
        return nil
    }

    func locateDirectory(_ path: String, traversingFrom from: AbsolutePath) -> AbsolutePath? {
        return nil
    }

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return []
    }

    func linkFile(atPath: AbsolutePath, toPath: AbsolutePath) throws {
    }

    func createFolder(_ path: AbsolutePath) throws {
    }

    func delete(_ path: AbsolutePath) throws {
    }

    func isFolder(_ path: AbsolutePath) -> Bool {
        return false
    }

    func touch(_ path: AbsolutePath) throws {
    }

    func contentsOfDirectory(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return []
    }
}
