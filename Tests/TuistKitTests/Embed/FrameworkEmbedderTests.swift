import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class FrameworkEmbedderTests: TuistUnitTestCase {
    var subject: FrameworkEmbedder!
    var fm: FileManager!

    override func setUp() {
        super.setUp()
        subject = FrameworkEmbedder()
        fm = FileManager.default
    }

    override func tearDown() {
        subject = nil
        fm = nil
        super.tearDown()
    }

    func test_embed_with_codesigning() throws {
        XCTAssertNoThrow(try withEnvironment(codeSigningIdentity: "iPhone Developer") { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            let binPath = env.frameworksPath().appending(RelativePath("xpm.framework/xpm"))
            system.succeedCommand([
                "/usr/bin/lipo", "-info", universalFrameworkPath().appending(component: "xpm").pathString,
            ], output: "Architectures in the fat file: \(binPath) are: x86_64 arm64")
            system.succeedCommand([
                "/usr/bin/xcrun",
                "codesign", "--force", "--sign", "iPhone Developer", "--preserve-metadata=identifier,entitlements", env.frameworksPath().appending(.init("xpm.framework")).pathString,
            ])
            try subject.embed(frameworkPath: frameworkPath, environment: env)
        })
    }

    func test_embed_with_no_codesigning() {
        XCTAssertNoThrow(try withEnvironment(codeSigningIdentity: nil) { srcRoot, env in
            let frameworkPath = universalFrameworkPath().relative(to: srcRoot)
            let binPath = env.frameworksPath().appending(RelativePath("xpm.framework/xpm"))
            system.succeedCommand([
                "/usr/bin/lipo", "-info", universalFrameworkPath().appending(component: "xpm").pathString,
            ], output: "Architectures in the fat file: \(binPath) are: x86_64 arm64")
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
                                                 codeSigningIdentity: codeSigningIdentity,
                                                 codeSigningAllowed: true)
        try assert(srcRootPath, environment)
    }
}
