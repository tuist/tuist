import Foundation
import Path
import Testing

@testable import TuistSupport
@testable import TuistTesting

struct AbsolutePathExtrasTests {
    @Test
    func test_commonAncestor_siblings() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/B")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        #expect(result == try AbsolutePath(validating: "/path/to"))
    }

    @Test
    func test_commonAncestor_parent() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        #expect(result == try AbsolutePath(validating: "/path/to"))
    }

    @Test
    func test_commonAncestor_none() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/another/path")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        #expect(result == try AbsolutePath(validating: "/"))
    }

    @Test
    func test_commonAncestor_commutative() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/B")

        // When
        let resultA = pathA.commonAncestor(with: pathB)
        let resultB = pathB.commonAncestor(with: pathA)

        // Then
        #expect(resultA == resultB)
    }

    @Test
    func test_isInOpaqueDirectory() throws {
        #expect(!try AbsolutePath(validating: "/test/directory.bundle").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.xcassets").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.xcassets").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.scnassets").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.xcdatamodeld").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.docc").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.playground").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.bundle").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.xcmappingmodel").isInOpaqueDirectory)

        #expect(!try AbsolutePath(validating: "/").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.notopaque/file.notopaque").isInOpaqueDirectory)
        #expect(!try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle/file.png").isInOpaqueDirectory)

        #expect(try AbsolutePath(validating: "/test/directory.bundle/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.xcassets/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.xcassets/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.scnassets/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.xcdatamodeld/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.docc/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.playground/file.png").isInOpaqueDirectory)
        #expect(try AbsolutePath(validating: "/test/directory.xcmappingmodel/file.png").isInOpaqueDirectory)
    }

    @Test
    func test_opaqueDirectory() async throws {
        for directory in [
            "/test/directory.bundle",
            "/test/directory.xcassets",
            "/test/directory.scnassets",
            "/test/directory.xcdatamodeld",
            "/test/directory.docc",
            "/test/directory.xcmappingmodel",
        ] as [AbsolutePath] {
            #expect(directory.opaqueParentDirectory() == nil)
        }

        #expect(try AbsolutePath(validating: "/").opaqueParentDirectory() == nil)
        #expect(try AbsolutePath(validating: "/test/directory.notopaque/file.notopaque").opaqueParentDirectory() == nil)
        #expect(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle").opaqueParentDirectory() == nil)
        #expect(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle/file.png").opaqueParentDirectory() == try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle"))

        for file in [
            "/test/directory.bundle/file.png",
            "/test/directory.xcassets/file.png",
            "/test/directory.scnassets/file.png",
            "/test/directory.xcdatamodeld/file.png",
            "/test/directory.docc/file.png",
            "/test/directory.xcmappingmodel/file.png",
        ] as [AbsolutePath] {
            #expect(file.opaqueParentDirectory() == file.parentDirectory)
        }
    }
}
