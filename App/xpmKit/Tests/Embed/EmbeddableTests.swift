import Basic
import Foundation
import XCTest
@testable import xpmKit

final class EmbeddableTests: XCTestCase {
    var fm: FileManager!

    override func setUp() {
        super.setUp()
        fm = FileManager.default
    }

    func test_embeddableError_type() {
        XCTAssertEqual(EmbeddableError.missingBundleExecutable(AbsolutePath("/path")).type, .abort)
        XCTAssertEqual(EmbeddableError.unstrippableNonFatEmbeddable(AbsolutePath("/path")).type, .abort)
    }

    func test_embeddableError_description() {
        XCTAssertEqual(EmbeddableError.missingBundleExecutable(AbsolutePath("/path")).description, "Couldn't find executable in bundle at path /path")
        XCTAssertEqual(EmbeddableError.unstrippableNonFatEmbeddable(AbsolutePath("/path")).description, "Can't strip architectures from the non-fat package at path /path")
    }

    func test_embeddableType() {
        XCTAssertEqual(EmbeddableType.framework.rawValue, "FMWK")
        XCTAssertEqual(EmbeddableType.bundle.rawValue, "BNDL")
        XCTAssertEqual(EmbeddableType.dSYM.rawValue, "dSYM")
    }

    func test_constants() {
        XCTAssertEqual(Embeddable.Constants.lipoArchitecturesMessage, "Architectures in the fat file:")
        XCTAssertEqual(Embeddable.Constants.lipoNonFatFileMessage, "Non-fat file:")
    }

    func test_binaryPath_whenFramework() throws {
        try withUniversalFramework {
            let name = $0.path.components.last!.split(separator: ".").first!
            let expected = $0.path.appending(component: String(name))
            try XCTAssertEqual($0.binaryPath(), expected)
        }
    }

    func test_binaryPath_whenDSYM() throws {
        try withDSYM {
            let expected = $0.path.appending(RelativePath("Contents/Resources/DWARF/xpm"))
            try XCTAssertEqual($0.binaryPath(), expected)
        }
    }

    func test_packageType_whenFramework() throws {
        try withUniversalFramework {
            XCTAssertEqual($0.packageType(), .framework)
        }
    }

    func test_packageType_whenDSYM() throws {
        try withDSYM {
            XCTAssertEqual($0.packageType(), .dSYM)
        }
    }

    func test_architectures_whenFramework() throws {
        try withUniversalFramework {
            // The fixture framework is a universal framework.
            try XCTAssertEqual($0.architectures(), ["x86_64", "arm64"])
        }
    }

    func test_architectures_whenDSYM() throws {
        try withDSYM {
            // The fixture dSYM was compiled for the simulator architecture.
            try XCTAssertEqual($0.architectures(), ["arm64"])
        }
    }

    func test_strip_whenFramework() throws {
        try withUniversalFramework {
            XCTAssertTrue(fm.fileExists(atPath: $0.path.appending(component: "Headers").asString))
            XCTAssertTrue(fm.fileExists(atPath: $0.path.appending(component: "PrivateHeaders").asString))
            XCTAssertTrue(fm.fileExists(atPath: $0.path.appending(component: "Modules").asString))
            try XCTAssertEqual($0.architectures(), ["x86_64", "arm64"])

            try $0.strip(keepingArchitectures: ["x86_64"])

            try XCTAssertEqual($0.architectures(), ["x86_64"])
            XCTAssertFalse(fm.fileExists(atPath: $0.path.appending(component: "Headers").asString))
            XCTAssertFalse(fm.fileExists(atPath: $0.path.appending(component: "PrivateHeaders").asString))
            XCTAssertFalse(fm.fileExists(atPath: $0.path.appending(component: "Modules").asString))
        }
    }

    func test_strip_throws() throws {
        try withDSYM {
            let path = $0.path
            XCTAssertThrowsError(try $0.strip(keepingArchitectures: [])) {
                XCTAssertEqual($0 as? EmbeddableError, EmbeddableError.unstrippableNonFatEmbeddable(path))
            }
        }
    }

    func test_uuids_whenFramework() throws {
        try withUniversalFramework {
            let expected: Set<UUID> = Set(arrayLiteral: UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C")!,
                                          UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98")!)
            try XCTAssertEqual($0.uuids(), expected)
        }
    }

    func test_uuids_whensDSYM() throws {
        try withDSYM {
            let expected: Set<UUID> = Set(arrayLiteral: UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98")!)
            try XCTAssertEqual($0.uuids(), expected)
        }
    }

    func test_bcSymbolMapsForFramework() throws {
        try withUniversalFramework {
            let path = $0.path
            var symbolMapsPaths: [AbsolutePath] = []
            try $0.uuids().forEach {
                let symbolMapPath = path.parentDirectory.appending(component: "\($0.uuidString).bcsymbolmap")
                symbolMapsPaths.append(symbolMapPath)
                fm.createFile(atPath: symbolMapPath.asString,
                              contents: nil,
                              attributes: [:])
            }
            try XCTAssertEqual($0.bcSymbolMapsForFramework(), symbolMapsPaths)
        }
    }

    fileprivate func withUniversalFramework(action: (Embeddable) throws -> Void) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let testsPath = AbsolutePath(#file).parentDirectory.parentDirectory
        let frameworkPath = testsPath.appending(RelativePath("fixtures/xpm.framework"))
        let frameworkTmpPath = tmpDir.path.appending(component: "xpm.framework")
        try fm.copyItem(atPath: frameworkPath.asString,
                        toPath: frameworkTmpPath.asString)
        let embeddable = Embeddable(path: frameworkTmpPath)
        try action(embeddable)
    }

    fileprivate func withDSYM(action: (Embeddable) throws -> Void) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let testsPath = AbsolutePath(#file).parentDirectory.parentDirectory
        let frameworkPath = testsPath.appending(RelativePath("fixtures/xpm.framework.dSYM"))
        let frameworkTmpPath = tmpDir.path.appending(component: "xpm.framework.dSYM")
        try fm.copyItem(atPath: frameworkPath.asString,
                        toPath: frameworkTmpPath.asString)
        let embeddable = Embeddable(path: frameworkTmpPath)
        try action(embeddable)
    }
}
