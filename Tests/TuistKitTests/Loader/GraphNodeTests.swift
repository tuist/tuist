import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class PrecompiledNodeTests: XCTestCase {
    var shell: MockShell!

    override func setUp() {
        super.setUp()
        shell = MockShell()
    }

    func test_architecture_rawValues() {
        XCTAssertEqual(PrecompiledNode.Architecture.x8664.rawValue, "x86_64")
        XCTAssertEqual(PrecompiledNode.Architecture.i386.rawValue, "i386")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7.rawValue, "armv7")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7s.rawValue, "armv7s")
    }
}

final class FrameworkNodeTests: XCTestCase {
    var shell: MockShell!
    var subject: FrameworkNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        shell = MockShell()
        path = AbsolutePath("/test.framework")
        subject = FrameworkNode(path: path)
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.asString, "/test.framework/test")
    }

    func test_architectures() throws {
        shell.runAndOutputStub = { command, _ in
            if command.joined(separator: " ") == "lipo -info /test.framework/test" {
                return "Non-fat file: path is architecture: x86_64"
            }
            return ""
        }
        try XCTAssertEqual(subject.architectures(shell: shell).first, .x8664)
    }

    func test_linking() {
        shell.runAndOutputStub = { command, _ in
            if command.joined(separator: " ") == "file /test.framework/test" {
                return "whatever dynamically linked"
            }
            return ""
        }
        try XCTAssertEqual(subject.linking(shell: shell), .dynamic)
    }
}

final class LibraryNodeTests: XCTestCase {
    var shell: MockShell!
    var subject: LibraryNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        shell = MockShell()
        path = AbsolutePath("/test.a")
        subject = LibraryNode(path: path, publicHeaders: AbsolutePath("/headers"))
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.asString, "/test.a")
    }

    func test_architectures() throws {
        shell.runAndOutputStub = { command, _ in
            if command.joined(separator: " ") == "lipo -info /test.a" {
                return "Non-fat file: path is architecture: x86_64"
            }
            return ""
        }
        try XCTAssertEqual(subject.architectures(shell: shell).first, .x8664)
    }

    func test_linking() {
        shell.runAndOutputStub = { command, _ in
            if command.joined(separator: " ") == "file /test.a" {
                return "whatever dynamically linked"
            }
            return ""
        }
        try XCTAssertEqual(subject.linking(shell: shell), .dynamic)
    }
}
