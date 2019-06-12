import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class GraphNodeTests: XCTestCase {
    func test_set() {
        // Given
        let a = GraphNode(path: "/path/a")
        let b = GraphNode(path: "/path/b")
        let c1 = TargetNode(project: .test(path: "/path/c"),
                            target: .test(name: "c1"),
                            dependencies: [])
        let c2 = TargetNode(project: .test(path: "/path/c"),
                            target: .test(name: "c2"),
                            dependencies: [])
        let d = LibraryNode(path: "/path/a", publicHeaders: "/path/to/headers")
        let e = LibraryNode(path: "/path/c", publicHeaders: "/path/to/headers")

        // When
        var set = Set<GraphNode>()
        set.insert(a)
        set.insert(b)
        set.insert(c1)
        set.insert(c2)
        set.insert(d)
        set.insert(e)

        // Then
        XCTAssertEqual(set.count, 6)
    }

    func test_equality() {
        // Given
        let a1 = GraphNode(path: "/a")
        let a2 = GraphNode(path: "/a")
        let b = GraphNode(path: "/b")

        // When / Then
        XCTAssertEqual(a1, a2)
        XCTAssertNotEqual(a2, b)
        XCTAssertEqual(b, b)
    }

    func test_subclass_equality() {
        // Given
        let a = GraphNode(path: "/a")
        let b = TargetNode(project: .test(path: "/a"), target: .test(), dependencies: [])
        let c = LibraryNode(path: "/a", publicHeaders: "/path/to/headers")

        // When / Then
        let all = [a, b, c]
        XCTAssertEqual(a, a)
        XCTAssertEqual(b, b)
        XCTAssertEqual(c, c)

        for lhs in all.enumerated() {
            for rhs in all.enumerated() where lhs.offset != rhs.offset {
                XCTAssertNotEqual(lhs.element, rhs.element)
            }
        }
    }
}

final class TargetNodeTests: XCTestCase {
    func test_equality() {
        // Given
        let c1 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c"),
                            dependencies: [])
        let c2 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c"),
                            dependencies: [])
        let c3 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c3"),
                            dependencies: [])
        let d = TargetNode(project: .test(path: "/d"),
                           target: .test(name: "c"),
                           dependencies: [])

        // When / Then
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c2, c3)
        XCTAssertNotEqual(c1, d)
        XCTAssertEqual(d, d)
    }

    func test_equality_asGraphNodes() {
        // Given
        let c1: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c2: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c3: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c3"),
                                       dependencies: [])
        let d: GraphNode = TargetNode(project: .test(path: "/d"),
                                      target: .test(name: "c"),
                                      dependencies: [])

        // When / Then
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c2, c3)
        XCTAssertNotEqual(c1, d)
    }
}

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
        XCTAssertEqual(subject.binaryPath.pathString, "/test.framework/test")
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
        XCTAssertEqual(subject.binaryPath.pathString, "/test.a")
    }

    func test_architectures() throws {
        system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")
        try XCTAssertEqual(subject.architectures(system: system).first, .x8664)
    }

    func test_linking() {
        system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")
        try XCTAssertEqual(subject.linking(system: system), .dynamic)
    }

    func test_equality() {
        // Given
        let a1 = LibraryNode(path: "/a", publicHeaders: "/a/header", swiftModuleMap: "/a/swiftmodulemap")
        let a2 = LibraryNode(path: "/a", publicHeaders: "/a/header/2", swiftModuleMap: "/a/swiftmodulemap")
        let b = LibraryNode(path: "/b", publicHeaders: "/b/header", swiftModuleMap: "/b/swiftmodulemap")

        // When / Then
        XCTAssertEqual(a1, a1)
        XCTAssertNotEqual(a1, a2)
        XCTAssertNotEqual(a2, b)
        XCTAssertNotEqual(a1, b)
    }
}

final class SDKNodeTests: XCTestCase {
    func test_sdk_supportedTypes() throws {
        // Given
        let libraries = [
            "Foo.framework",
            "libBar.tbd"
        ]
        
        // When / Then
        XCTAssertNoThrow(try libraries.map { try SDKNode(name: $0, status: .required) })
    }
    
    func test_sdk_usupportedTypes() throws {
        XCTAssertThrowsError(try SDKNode(name: "FooBar", status: .required)) { error in
            XCTAssertEqual(error as? SDKNode.Error, .unsupported(sdk: "FooBar"))
        }
    }
    
    func test_sdk_errors() {
        XCTAssertEqual(SDKNode.Error.unsupported(sdk: "Foo").type, .abort)
    }
    
    func test_sdk_paths() throws {
        // Given
        let libraries = [
            "Foo.framework",
            "libBar.tbd"
        ]
        
        // When
        let nodes = try libraries.map { try SDKNode(name: $0, status: .required) }
        
        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/System/Library/Frameworks/Foo.framework",
            "/usr/lib/libBar.tbd"
        ])
    }
}
