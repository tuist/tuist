import Basic
import Foundation
import XCTest
@testable import TuistKit
@testable import TuistCoreTesting

final class FrameworkEmbedderErrorTests: XCTestCase {
    var subject: FrameworkEmbedder!
    var fm: FileManager!
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        subject = FrameworkEmbedder(system: system)
        fm = FileManager.default
    }

    func test_embed_when_actionIsInstall() throws {
        try withEnvironment(action: .install) { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            try subject.embed(frameworkPath: frameworkPath,
                              environment: env)
            let outputFrameworkPath = srcRoot.appending(RelativePath("built_products_dir/frameworks/xpm.framework"))
            let outputDSYMPath = srcRoot.appending(RelativePath("built_products_dir/xpm.framework.dSYM"))
            XCTAssertTrue(fm.fileExists(atPath: outputFrameworkPath.pathString))
            XCTAssertTrue(fm.fileExists(atPath: outputDSYMPath.pathString))
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
            XCTAssertTrue(fm.fileExists(atPath: outputFrameworkPath.pathString))
            XCTAssertTrue(fm.fileExists(atPath: outputDSYMPath.pathString))
            XCTAssertEqual(try Embeddable(path: outputFrameworkPath).architectures(), ["arm64"])
            XCTAssertEqual(try Embeddable(path: outputDSYMPath).architectures(), ["arm64"])
        }
    }
    
    func test_embed_with_codesigning() throws {
        XCTAssertNoThrow(try withEnvironment(codeSigningIdentity: "iPhone Developer") { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            system.succeedCommand([
                "/usr/bin/xcrun",
                "codesign", "--force", "--sign", "iPhone Developer", "--preserve-metadata=identifier,entitlements", env.frameworksPath().appending(.init("xpm.framework")).pathString
            ])
            try subject.embed(frameworkPath: frameworkPath, environment: env)
        })
    }
    
    func test_embed_with_no_codesigning() {
        XCTAssertNoThrow(try withEnvironment(codeSigningIdentity: nil) { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            try subject.embed(frameworkPath: frameworkPath, environment: env)
            XCTAssertFalse(
                system.called("/usr/bin/xcrun",
                              "codesign", "--force", "--sign", "iPhone Developer", "--preserve-metadata=identifier,entitlements", env.frameworksPath().appending(.init("xpm.framework")).pathString)
            )
        })
    }

    private func universalFrameworkPath() -> AbsolutePath {
        let testsPath = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory
        return testsPath.appending(RelativePath("Fixtures/xpm.framework"))
    }

    private func withEnvironment(action: XcodeBuild.Action = .install,
                                 codeSigningIdentity: String? = nil,
                                 assert: (AbsolutePath, XcodeBuild.Environment) throws -> Void) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let frameworksPath = "frameworks"
        let srcRootPath = tmpDir.path
        let builtProductsDir = tmpDir.path.appending(component: "built_products_dir")
        let targetBuildDir = tmpDir.path.appending(component: "target_build_dir")
        let validArchs = ["arm64"]
        func createDirectory(path: AbsolutePath) throws {
            try FileManager.default.createDirectory(atPath: path.pathString,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        try createDirectory(path: srcRootPath)
        try createDirectory(path: builtProductsDir)
        try createDirectory(path: targetBuildDir)
        let environment = XcodeBuild.Environment(configuration: "Debug",
                                                 frameworksFolderPath: frameworksPath,
                                                 builtProductsDir: builtProductsDir.pathString,
                                                 targetBuildDir: targetBuildDir.pathString,
                                                 validArchs: validArchs,
                                                 srcRoot: srcRootPath.pathString,
                                                 action: action,
                                                 codeSigningIdentity: codeSigningIdentity)
        try assert(srcRootPath, environment)
    }
}
