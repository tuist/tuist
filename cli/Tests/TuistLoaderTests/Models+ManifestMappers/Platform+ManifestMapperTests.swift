import Foundation
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct PlatformManifestMapperTests {
    @Test func platform_iOS() throws {
        let manifest: ProjectDescription.Platform = .iOS
        let model = try XcodeGraph.Platform.from(manifest: manifest)
        #expect(model == .iOS)
    }

    @Test func platform_tvOS() throws {
        let manifest: ProjectDescription.Platform = .tvOS
        let model = try XcodeGraph.Platform.from(manifest: manifest)
        #expect(model == .tvOS)
    }

    @Test func platform_macOS() throws {
        let manifest: ProjectDescription.Platform = .macOS
        let model = try XcodeGraph.Platform.from(manifest: manifest)
        #expect(model == .macOS)
    }

    @Test func platform_watchOS() throws {
        let manifest: ProjectDescription.Platform = .watchOS
        let model = try XcodeGraph.Platform.from(manifest: manifest)
        #expect(model == .watchOS)
    }
}
