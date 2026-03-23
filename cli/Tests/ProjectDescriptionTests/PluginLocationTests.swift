import Testing
import TuistTesting
@testable import ProjectDescription

struct PluginLocationTests {
    @Test func test_codable_local() throws {
        let subject = PluginLocation.local(path: .path("/some/path"))
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_codable_gitWithTag() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", tag: "1.0.0")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_codable_gitWithSha() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", sha: "64d8d24f")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_codable_gitWithDirectory() throws {
        let subject = PluginLocation.git(url: "https://git.com/repo.git", tag: "1.0.0", directory: "directory")
        #expect(try isCodableRoundTripable(subject))
    }
}
