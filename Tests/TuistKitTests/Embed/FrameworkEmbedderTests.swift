import Basic
import Foundation
import XCTest
@testable import TuistKit

final class FrameworkEmbedderErrorTests: XCTestCase {
    var subject: FrameworkEmbedder!
    var fm: FileManager!

    override func setUp() {
        super.setUp()
        subject = FrameworkEmbedder()
        fm = FileManager.default
    }

    func test_embed_when_actionIsInstall() throws {
        try withEnvironment(action: .install) { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            try subject.embed(frameworkPath: frameworkPath,
                              environment: env)
            let outputFrameworkPath = srcRoot.appending(RelativePath("built_products_dir/frameworks/xpm.framework"))
            let outputDSYMPath = srcRoot.appending(RelativePath("built_products_dir/xpm.framework.dSYM"))
            XCTAssertTrue(fm.fileExists(atPath: outputFrameworkPath.asString))
            XCTAssertTrue(fm.fileExists(atPath: outputDSYMPath.asString))
            XCTAssertEqual(try Embeddable(path: outputFrameworkPath).architectures(), ["arm64"])
            XCTAssertEqual(try Embeddable(path: outputDSYMPath).architectures(), ["arm64"])
        }
    }

    func test_embed_when_actionIsNotInstall() throws {
        try withEnvironment(action: .build) { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            try subject.embed(frameworkPath: frameworkPath,
                              environment: env)
            let outputFrameworkPath = srcRoot.appending(RelativePath("target_build_dir/frameworks/xpm.framework"))
            let outputDSYMPath = srcRoot.appending(RelativePath("target_build_dir/xpm.framework.dSYM"))
            XCTAssertTrue(fm.fileExists(atPath: outputFrameworkPath.asString))
            XCTAssertTrue(fm.fileExists(atPath: outputDSYMPath.asString))
            XCTAssertEqual(try Embeddable(path: outputFrameworkPath).architectures(), ["arm64"])
            XCTAssertEqual(try Embeddable(path: outputDSYMPath).architectures(), ["arm64"])
        }
    }

    private func universalFrameworkPath() -> AbsolutePath {
        let testsPath = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory
        return testsPath.appending(RelativePath("Fixtures/xpm.framework"))
    }

    private func withEnvironment(action: XcodeBuild.Action = .install,
                                 assert: (AbsolutePath, XcodeBuild.Environment) throws -> Void) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let frameworksPath = "frameworks"
        let srcRootPath = tmpDir.path
        let builtProductsDir = tmpDir.path.appending(component: "built_products_dir")
        let targetBuildDir = tmpDir.path.appending(component: "target_build_dir")
        let validArchs = ["arm64"]
        func createDirectory(path: AbsolutePath) throws {
            try FileManager.default.createDirectory(atPath: path.asString,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        try createDirectory(path: srcRootPath)
        try createDirectory(path: builtProductsDir)
        try createDirectory(path: targetBuildDir)
        let environment = XcodeBuild.Environment(configuration: "Debug",
                                                 frameworksFolderPath: frameworksPath,
                                                 builtProductsDir: builtProductsDir.asString,
                                                 targetBuildDir: targetBuildDir.asString,
                                                 validArchs: validArchs,
                                                 srcRoot: srcRootPath.asString,
                                                 action: action)
        try assert(srcRootPath, environment)
    }
}
