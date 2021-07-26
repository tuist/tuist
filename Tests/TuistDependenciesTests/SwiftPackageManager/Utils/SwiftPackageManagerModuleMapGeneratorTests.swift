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
        try test_generate(for: .custom)
    }

    func test_generate_when_umbrella_header() throws {
        try test_generate(for: .header("/Absolute/Public/Headers/Path/Module.h"))
    }

    func test_generate_when_nested_umbrella_header() throws {
        try test_generate(for: .header("/Absolute/Public/Headers/Path/Module/Module.h"))
    }

    func test_generate_when_umbrella_directory() throws {
        try test_generate(for: .directory("/Absolute/Public/Headers/Path"))
    }

    func test_generate_when_no_headers() throws {
        try test_generate(for: .none)
    }

    private func test_generate(for moduleMapType: SwiftPackageManagerModuleMapGenerator.ModuleMapType) throws {
        var writeCalled = false
        fileHandler.stubExists = { path in
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
        fileHandler.stubWrite = { content, path, atomically in
            writeCalled = true
            let expectedContent: String
            switch moduleMapType {
            case .none, .custom:
                XCTFail("FileHandler.write should not be called")
                return
            case let .header(path):
                expectedContent = """
                module Module {
                    umbrella header "\(path.pathString)"
                    export *
                }

                """
            case .directory:
                expectedContent = """
                module Module {
                    umbrella "/Absolute/Public/Headers/Path"
                    export *
                }

                """
            }
            XCTAssertEqual(content, expectedContent)
            XCTAssertEqual(path, "/Absolute/Public/Headers/Path/Module.modulemap")
            XCTAssertTrue(atomically)
        }
        let moduleMapPath = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        switch moduleMapType {
        case .none:
            XCTAssertNil(moduleMapPath)
        case .custom:
            XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/module.modulemap")
        case .header, .directory:
            XCTAssertEqual(moduleMapPath, "/Absolute/Public/Headers/Path/Module.modulemap")
        }
        switch moduleMapType {
        case .none, .custom:
            XCTAssertFalse(writeCalled)
        case .header, .directory:
            XCTAssertTrue(writeCalled)
        }
    }
}
