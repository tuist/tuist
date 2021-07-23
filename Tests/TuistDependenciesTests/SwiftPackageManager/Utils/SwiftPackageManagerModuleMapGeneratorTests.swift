import TSCBasic
import TuistSupportTesting
import XCTest

@testable import TuistDependencies

class SwiftPackageManagerModuleMapGeneratorTests: TuistTestCase {
    private var subject: SwiftPackageManagerModuleMapGenerator!

    override func setUp() {
        super.setUp()
        subject = SwiftPackageManagerModuleMapGenerator()
    }

    override func tearDown() {
        fileHandler = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_when_custom_module_map() throws {
        fileHandler.stubExists = stubExists(for: .custom)
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/module.modulemap")
    }

    func test_generate_when_umbrella_header() throws {
        fileHandler.stubExists = stubExists(for: .header("/Absolute/Public/Headers/Path/Module.h"))
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/Module.modulemap")
    }

    func test_generate_when_nested_umbrella_header() throws {
        fileHandler.stubExists = stubExists(for: .header("/Absolute/Public/Headers/Path/Module/Module.h"))
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/Module.modulemap")
    }

    func test_generate_when_umbrella_directory() throws {
        fileHandler.stubExists = stubExists(for: .directory("/Absolute/Public/Headers/Path"))
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/Module.modulemap")
    }

    func test_generate_when_no_headers() throws {
        fileHandler.stubExists = stubExists(for: .none)
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertNil(moduleMapPath)
    }
}

private func stubExists(for moduleMapType: SwiftPackageManagerModuleMapGenerator.ModuleMapType) -> (AbsolutePath) -> Bool {
    return { path in
        switch path {
        case "/Absolute/Public/Headers/Path/module.modulemap":
            return moduleMapType == .custom
        case "/Absolute/Public/Headers/Path/Module.h":
            return moduleMapType == .header(path)
        case "/Absolute/Public/Headers/Path/Module/Module.h":
            return moduleMapType == .header(path)
        case "/Absolute/Public/Headers/Path":
            return moduleMapType == .directory(path)
        default:
            XCTFail("Unexpected exists call: \(path)")
            return false
        }
    }
}
