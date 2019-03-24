import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class PrecompiledNodeTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_architecture_rawValues() {
        XCTAssertEqual(PrecompiledNode.Architecture.x8664.rawValue, "x86_64")
        XCTAssertEqual(PrecompiledNode.Architecture.i386.rawValue, "i386")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7.rawValue, "armv7")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7s.rawValue, "armv7s")
    }
}

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

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.asString, "/test.framework/test")
    }

    func test_isCarthage() {
        XCTAssertFalse(subject.isCarthage)
        subject = FrameworkNode(path: AbsolutePath("/path/Carthage/Build/iOS/A.framework"))
        XCTAssertTrue(subject.isCarthage)
    }

    func test_architectures() throws {
        system.succeedCommand("/usr/bin/lipo -info /test.framework/test",
                              output: "Non-fat file: path is architecture: x86_64")
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_linking() {
        system.succeedCommand("/usr/bin/file", "/test.framework/test",
                              output: "whatever dynamically linked")
        try XCTAssertEqual(subject.linking(system: system), .dynamic)
    }
}

final class LibraryNodeTests: XCTestCase {
    var system: MockSystem!
    var subject: LibraryNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        path = AbsolutePath("/test.a")
        subject = LibraryNode(path: path, publicHeaders: AbsolutePath("/headers"))
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.asString, "/test.a")
    }

    func test_architectures() throws {
        system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_linking() {
        system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")
        try XCTAssertEqual(subject.linking(system: system), .dynamic)
    }
}
