import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct PathTests {
    @Test func codable_when_relativeToCurrentFile() throws {
        #expect(try isCodableRoundTripable(Path.relativeToCurrentFile("file.swift")))
    }

    @Test func codable_when_relativeToManifest() throws {
        #expect(try isCodableRoundTripable(Path.relativeToManifest("file.swift")))
    }

    @Test func codable_when_relativeToRoot() throws {
        #expect(try isCodableRoundTripable(Path.relativeToRoot("file.swift")))
    }

    @Test func init_when_the_path_is_prefixed_with_two_slashes() {
        let path: Path = "//file.swift"
        #expect(path == Path.relativeToRoot("file.swift"))
    }

    @Test func init_when_the_path_is_not_prefixed() {
        let path: Path = "file.swift"
        #expect(path == Path.relativeToManifest("file.swift"))
    }
}
