import Basic
import Foundation
import XCTest

import TuistCoreTesting
@testable import TuistGenerator

final class FrameworkNodeTests: XCTestCase {
    var system: MockSystem!
    var subject: FrameworkNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        path = AbsolutePath("/test.framework")
        subject = FrameworkNode(path: path)
    }

    func test_name() {
        XCTAssertEqual(subject.name, "test")
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.pathString, "/test.framework/test")
    }

    func test_isCarthage() {
        XCTAssertFalse(subject.isCarthage)
        subject = FrameworkNode(path: AbsolutePath("/path/Carthage/Build/iOS/A.framework"))
        XCTAssertTrue(subject.isCarthage)
    }

    func test_architectures_when_nonFatFramework() throws {
        system.succeedCommand("/usr/bin/lipo -info /test.framework/test",
                              output: "Non-fat file: path is architecture: x86_64")
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_architectures_when_fatFramework() throws {
        system.succeedCommand("/usr/bin/lipo -info /test.framework/test",
                              output: "Architectures in the fat file: /path/xpm.framework/xpm are: x86_64 arm64")
        try XCTAssertTrue(subject.architectures(system: system).contains(.x8664))
        try XCTAssertTrue(subject.architectures(system: system).contains(.arm64))
    }

    func test_linking() {
        system.succeedCommand("/usr/bin/file", "/test.framework/test",
                              output: "whatever dynamically linked")
        try XCTAssertEqual(subject.linking(system: system), .dynamic)
    }

    func test_encode() {
        // Given
        let framework = FrameworkNode(path: fixturePath(path: RelativePath("xpm.framework")))
        let expected = """
        {
        "path": "\(framework.path)",
        "architectures": ["x86_64", "arm64"],
        "name": "xpm",
        "type": "precompiled",
        "product": "framework"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(framework, expected)
    }
}
