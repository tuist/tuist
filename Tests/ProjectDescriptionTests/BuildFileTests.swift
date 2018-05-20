import Foundation
@testable import ProjectDescription
import XCTest

final class SourcesBuildFileTests: XCTestCase {
    func test_toJSON() {
        let subject = SourcesBuildFile.sources("pattern",
                                               compilerFlags: "flags")
        let json = subject.toJSON()
        let expected = "{\"compiler_flags\": \"flags\", \"pattern\": \"pattern\"}"
        XCTAssertEqual(json.toString(), expected)
    }
}

final class BaseResourcesBuildFileTests: XCTestCase {
    func test_toJSON() {
        let subject = BaseResourcesBuildFile("pattern")
        let json = subject.toJSON()
        let expected = "{\"pattern\": \"pattern\", \"type\": \"default\"}"
        XCTAssertEqual(json.toString(), expected)
    }
}

final class CoreDataModelBuildFileTests: XCTestCase {
    func test_toJSON() {
        let subject = CoreDataModelBuildFile("path",
                                             currentVersion: "current")
        let json = subject.toJSON()
        let expected = "{\"current_version\": \"current\", \"path\": \"path\", \"type\": \"core_data\"}"
        XCTAssertEqual(json.toString(), expected)
    }
}

final class HeadersBuildFileTests: XCTestCase {
    func test_toJSON() {
        let subject = HeadersBuildFile("pattern",
                                       accessLevel: .public)
        let json = subject.toJSON()
        let expected = "{\"access_level\": \"public\", \"pattern\": \"pattern\"}"
        XCTAssertEqual(json.toString(), expected)
    }
}
