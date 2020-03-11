import Foundation
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestTests: TuistUnitTestCase {
    func test_fileName() {
        XCTAssertEqual(Manifest.project.fileName, "Project.swift")
        XCTAssertEqual(Manifest.workspace.fileName, "Workspace.swift")
        XCTAssertEqual(Manifest.config.fileName, "Config.swift")
        XCTAssertEqual(Manifest.setup.fileName, "Setup.swift")
        XCTAssertEqual(Manifest.galaxy.fileName, "Galaxy.swift")
    }

    func test_deprecatedFileName() {
        XCTAssertEqual(Manifest.config.deprecatedFileName, "TuistConfig.swift")
    }
}
