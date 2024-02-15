import Foundation
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestTests: TuistUnitTestCase {
    func test_fileName() throws {
        let temporaryPath = try temporaryPath().appending(component: "folder")

        XCTAssertEqual(Manifest.project.fileName(temporaryPath), "Project.swift")
        XCTAssertEqual(Manifest.workspace.fileName(temporaryPath), "Workspace.swift")
        XCTAssertEqual(Manifest.config.fileName(temporaryPath), "Config.swift")
        XCTAssertEqual(Manifest.package.fileName(temporaryPath), "Package.swift")
        XCTAssertEqual(Manifest.packageSettings.fileName(temporaryPath), "Package.swift")
        XCTAssertEqual(Manifest.plugin.fileName(temporaryPath), "Plugin.swift")
        XCTAssertEqual(Manifest.template.fileName(temporaryPath), "folder.swift")
    }
}
