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
        subject = nil
        super.tearDown()
    }

    func test_generate_when_no_headers() throws {
        try test_generate(for: .none)
    }

    func test_generate_when_custom_module_map() throws {
        try test_generate(for: .custom)
    }

    func test_generate_when_umbrella_header() throws {
        try test_generate(for: .header)
    }

    func test_generate_when_nested_umbrella_header() throws {
        try test_generate(for: .nestedHeader)
    }

    private func test_generate(for moduleMapType: ModuleMapType) throws {
        var writeCalled = false
        fileHandler.stubContentsOfDirectory = { _ in
            switch moduleMapType {
            case .none:
                return []
            case .custom:
                return ["/Absolute/Public/Headers/Path/module.modulemap"]
            case .header:
                return ["/Absolute/Public/Headers/Path/Module.h"]
            case .nestedHeader:
                return ["/Absolute/Public/Headers/Path/Module/Module.h"]
            case .directory:
                return ["/Absolute/Public/Headers/Path/AnotherHeader.h"]
            }
        }
        fileHandler.stubExists = { path in
            switch path {
            case "/Absolute/Public/Headers/Path":
                return moduleMapType != .none
            case "/Absolute/Public/Headers/Path/module.modulemap":
                return moduleMapType == .custom
            case "/Absolute/Public/Headers/Path/Module.h":
                return moduleMapType == .header
            case "/Absolute/Public/Headers/Path/Module/Module.h":
                return moduleMapType == .nestedHeader
            default:
                XCTFail("Unexpected exists call: \(path)")
                return false
            }
        }
        fileHandler.stubWrite = { content, path, atomically in
            writeCalled = true
            let expectedContent: String
            switch moduleMapType {
            case .none, .custom, .header:
                XCTFail("FileHandler.write should not be called")
                return
            case .nestedHeader:
                expectedContent = """
                module Module {
                    umbrella header "/Absolute/Public/Headers/Path/Module/Module.h"
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
        let moduleMap = try subject.generate(moduleName: "Module", publicHeadersPath: "/Absolute/Public/Headers/Path")
        XCTAssertEqual(moduleMap.type, moduleMapType)
        switch moduleMapType {
        case .none, .header, .nestedHeader:
            XCTAssertNil(moduleMap.path)
        case .custom:
            XCTAssertEqual(moduleMap.path, "/Absolute/Public/Headers/Path/module.modulemap")
        case .directory:
            XCTAssertEqual(moduleMap.path, "/Absolute/Public/Headers/Path/Module.modulemap")
        }
        switch moduleMapType {
        case .none, .custom, .header, .nestedHeader:
            XCTAssertFalse(writeCalled)
        case .directory:
            XCTAssertTrue(writeCalled)
        }
    }
}
