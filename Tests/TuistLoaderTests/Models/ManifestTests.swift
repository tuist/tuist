import Foundation
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestTests: TuistUnitTestCase {
    func test_fileName() throws {
        let temporaryPath = try self.temporaryPath().appending(component: "folder")
        XCTAssertEqual(Manifest.project.fileName(temporaryPath), "Project.swift")
        XCTAssertEqual(Manifest.workspace.fileName(temporaryPath), "Workspace.swift")
        XCTAssertEqual(Manifest.config.fileName(temporaryPath), "Config.swift")
        XCTAssertEqual(Manifest.setup.fileName(temporaryPath), "Setup.swift")
        XCTAssertEqual(Manifest.galaxy.fileName(temporaryPath), "Galaxy.swift")
        XCTAssertEqual(Manifest.template.fileName(temporaryPath), "folder.swift")
    }

    func test_deprecatedFileName() {
        XCTAssertEqual(Manifest.config.deprecatedFileName, "TuistConfig.swift")
    }
}
