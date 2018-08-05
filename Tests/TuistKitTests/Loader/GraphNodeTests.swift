import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

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

    func test_architectures() throws {
        system.stub(args: ["lipo -info /test.framework/test"], stderror: nil, stdout: "Non-fat file: path is architecture: x86_64", exitstatus: 0)
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_linking() {
        system.stub(args: ["file", "/test.framework/test"], stderror: nil, stdout: "whatever dynamically linked", exitstatus: 0)
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
        system.stub(args: ["lipo", "-info", "/test.a"], stderror: nil, stdout: "Non-fat file: path is architecture: x86_64", exitstatus: 0)
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_linking() {
        system.stub(args: ["file /test.a"], stderror: nil, stdout: "whatever dynamically linked", exitstatus: 0)
        try XCTAssertEqual(subject.linking(system: system), .dynamic)
    }
}
