import Foundation
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ManifestTests: TuistUnitTestCase {
    func test_fileName() {
        XCTAssertEqual(Manifest.project.fileName, "Project.swift")
        XCTAssertEqual(Manifest.workspace.fileName, "Workspace.swift")
        XCTAssertEqual(Manifest.tuistConfig.fileName, "TuistConfig.swift")
        XCTAssertEqual(Manifest.setup.fileName, "Setup.swift")
        XCTAssertEqual(Manifest.galaxy.fileName, "Galaxy.swift")
    }
}
