import TSCBasic
import TuistSupportTesting
import XCTest

@testable import TuistLoader

class SwiftPackageManagerModuleMapGeneratorTests: TuistTestCase {
    private var subject: SwiftPackageManagerModuleMapGenerator!

    override func setUp() {
        super.setUp()
        subject = SwiftPackageManagerModuleMapGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_when_no_headers() throws {
        try test_generate(for: .none)
    }

    func test_generate_when_custom_module_map() throws {
        try test_generate(for: .custom("/Absolute/Public/Headers/Path/module.modulemap", umbrellaHeaderPath: nil))
    }

    func test_generate_when_umbrella_header() throws {
        try test_generate(for: .header(
            "/Absolute/Public/Headers/Path/Module.h",
            moduleMapPath: "/Absolute/PackageDir/Derived/Module.modulemap"
        ))
    }

    func test_generate_when_nested_umbrella_header() throws {
        try test_generate(for: .header(
            "/Absolute/Public/Headers/Path/Module/Module.h",
            moduleMapPath: "/Absolute/PackageDir/Derived/Module.modulemap"
        ))
    }

    private func test_generate(for moduleMap: ModuleMap) throws {
        var writeCalled = false
        fileHandler.stubContentsOfDirectory = { _ in
            switch moduleMap {
            case .none:
                return []
            case .custom:
                return ["/Absolute/Public/Headers/Path/module.modulemap"]
            case let .header(umbrellaHeaderPath, moduleMapPath: _):
                if umbrellaHeaderPath.parentDirectory.basename == "Module" {
                    return ["/Absolute/Public/Headers/Path/Module/Module.h"]
                } else {
                    return ["/Absolute/Public/Headers/Path/Module.h"]
                }
            case .directory:
                return ["/Absolute/Public/Headers/Path/AnotherHeader.h"]
            }
        }
        fileHandler.stubExists = { path in
            switch path {
            case "/Absolute/Public/Headers/Path":
                return moduleMap != .none
            case "/Absolute/Public/Headers/Path/module.modulemap":
                return moduleMap == .custom("/Absolute/Public/Headers/Path/module.modulemap", umbrellaHeaderPath: nil)
            case "/Absolute/Public/Headers/Path/Module.h":
                return moduleMap == .header(
                    AbsolutePath("/Absolute/Public/Headers/Path/Module.h"),
                    moduleMapPath: AbsolutePath("/Absolute/PackageDir/Derived/Module.modulemap")
                )
            case "/Absolute/Public/Headers/Path/Module/Module.h":
                return moduleMap == .header(
                    AbsolutePath("/Absolute/Public/Headers/Path/Module/Module.h"),
                    moduleMapPath: AbsolutePath("/Absolute/PackageDir/Derived/Module.modulemap")
                )
            case "/Absolute/PackageDir/Derived":
                return true
            default:
                XCTFail("Unexpected exists call: \(path)")
                return false
            }
        }
        fileHandler.stubWrite = { content, path, atomically in
            writeCalled = true
            let expectedContent: String
            switch moduleMap {
            case .none, .custom:
                XCTFail("FileHandler.write should not be called")
                return
            case let .header(umbrellaHeaderPath, moduleMapPath: _):
                if umbrellaHeaderPath.parentDirectory.basename == "Module" {
                    expectedContent = """
                    framework module Module {
                      umbrella header "/Absolute/Public/Headers/Path/Module/Module.h"

                      export *
                      module * { export * }
                    }
                    """
                } else {
                    expectedContent = """
                    framework module Module {
                      umbrella header "/Absolute/Public/Headers/Path/Module.h"

                      export *
                      module * { export * }
                    }
                    """
                }
            case .directory:
                expectedContent = """
                module Module {
                    umbrella "/Absolute/Public/Headers/Path"
                    export *
                }

                """
            }
            XCTAssertEqual(content, expectedContent)
            XCTAssertEqual(path, "/Absolute/PackageDir/Derived/Module.modulemap")
            XCTAssertTrue(atomically)
        }
        let got = try subject.generate(
            packageDirectory: "/Absolute/PackageDir",
            moduleName: "Module",
            publicHeadersPath: "/Absolute/Public/Headers/Path"
        )
        XCTAssertEqual(got, moduleMap)
        switch moduleMap {
        case .none, .custom:
            XCTAssertFalse(writeCalled)
        case .directory, .header:
            XCTAssertTrue(writeCalled)
        }
    }
}
