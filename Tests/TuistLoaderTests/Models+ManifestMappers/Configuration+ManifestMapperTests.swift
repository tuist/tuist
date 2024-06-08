import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ConfigurationManifestMapperTests: TuistUnitTestCase {
    func test_from_returns_nil_when_manifest_is_nil() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        // When
        let got = try XcodeGraph.Configuration.from(manifest: nil, generatorPaths: generatorPaths)

        // Then
        XCTAssertNil(got)
    }

    func test_from_returns_the_correct_value_when_manifest_is_not_nil() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let xcconfigPath = temporaryPath.appending(component: "Config.xcconfig")
        let settings: [String: ProjectDescription.SettingValue] = ["A": "B"]
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest: ProjectDescription.Configuration = .debug(
            name: .debug,
            settings: settings,
            xcconfig: .path(xcconfigPath.pathString)
        )

        // When
        let got = try XcodeGraph.Configuration.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        guard let aSetting = got?.settings["A"] else {
            XCTFail("Expected A to be defined")
            return
        }

        guard case let XcodeGraph.SettingValue.string(aString) = aSetting else {
            XCTFail("Expected A to be a string")
            return
        }
        XCTAssertEqual(aString, "B")
        XCTAssertEqual(got?.xcconfig?.pathString, xcconfigPath.pathString)
    }
}
