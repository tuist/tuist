import XCTest
@testable import ProjectDescription

final class PluginLocationTests: XCTestCase {
    func test_codable_local() throws {
        let subject = PluginLocation.local(path: .path("/some/path"))
        XCTAssertCodable(subject)
    }

    func test_codable_gitWithTag() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", tag: "1.0.0")
        XCTAssertCodable(subject)
    }

    func test_codable_gitWithSha() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", sha: "64d8d24f")
        XCTAssertCodable(subject)
    }

    func test_codable_gitWithDirectory() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", tag: "1.0.0", directory: "directory")
        XCTAssertCodable(subject)
    }
}
