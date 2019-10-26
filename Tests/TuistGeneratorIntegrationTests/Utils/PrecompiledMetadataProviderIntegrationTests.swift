
// func test_architectures() throws {
//    system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")
//    try XCTAssertEqual(subject.architectures().first, .x8664)
// }
//
// func test_linking() {
//    system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")
//    try XCTAssertEqual(subject.linking(), .dynamic)
// }

import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

// XCTAssertEqual(PrecompiledNode.Architecture.x8664.rawValue, "x86_64")
// XCTAssertEqual(PrecompiledNode.Architecture.i386.rawValue, "i386")
// XCTAssertEqual(PrecompiledNode.Architecture.armv7.rawValue, "armv7")
// XCTAssertEqual(PrecompiledNode.Architecture.armv7s.rawValue, "armv7s")

final class PrecompiledMetadataProviderIntegrationTests: TuistTestCase {
//    func test_architectures() throws {
//        // Given
//        let frameworkPath = temporaryFixture("xpm.framework")
//        let framework = FrameworkNode(path: frameworkPath)
//
//        // When
//        let got = try framework.architectures()
//
//        // Then
//        XCTAssertEqual(got.map(\.rawValue).sorted(), ["arm64", "x86_64"])
//    }
//
//    func test_uuids() throws {
//        // Given
//        let frameworkPath = temporaryFixture("xpm.framework")
//        let framework = FrameworkNode(path: frameworkPath)
//
//        // When
//        let got = try framework.uuids()
//
//        // Then
//        let expected = Set([
//            UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
//            UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
//        ])
//        XCTAssertEqual(got, expected)
//    }
//
//    fileprivate func temporaryFixture(_ pathString: String) -> AbsolutePath {
//        let path = RelativePath(pathString)
//        let fixturePath = self.fixturePath(path: path)
//        let destinationPath = (try! temporaryPath()).appending(component: path.basename)
//        try! FileHandler.shared.copy(from: fixturePath, to: destinationPath)
//        return destinationPath
//    }
}
