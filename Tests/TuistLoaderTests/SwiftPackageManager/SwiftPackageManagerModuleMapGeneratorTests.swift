import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistSupportTesting
import XCTest

@testable import TuistLoader

final class SwiftPackageManagerModuleMapGeneratorTests: TuistTestCase {
    private var subject: SwiftPackageManagerModuleMapGenerator!
    private var contentHasher: MockContentHashing!

    override func setUp() {
        super.setUp()
        contentHasher = MockContentHashing()
        subject = SwiftPackageManagerModuleMapGenerator(contentHasher: contentHasher)

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 }
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
        var writeCount = 0
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
            writeCount += 1
            guard let expectedContent = self.expectedContent(for: moduleMap) else {
                XCTFail("FileHandler.write should not be called")
                return
            }

            XCTAssertEqual(content, expectedContent)
            XCTAssertEqual(path, "/Absolute/PackageDir/Derived/Module.modulemap")
            XCTAssertTrue(atomically)
        }

        var hash: String? = nil

        given(contentHasher)
            .hash(path: .any)
            .willProduce { hash ?? $0.pathString }

        let got = try subject.generate(
            packageDirectory: "/Absolute/PackageDir",
            moduleName: "Module",
            publicHeadersPath: "/Absolute/Public/Headers/Path"
        )

        // Set hasher for path on disk
        hash = expectedContent(for: moduleMap)

        // generate a 2nd time to validate that we dont write content that is already on disk
        let _ = try subject.generate(
            packageDirectory: "/Absolute/PackageDir",
            moduleName: "Module",
            publicHeadersPath: "/Absolute/Public/Headers/Path"
        )

        XCTAssertEqual(got, moduleMap)
        switch moduleMap {
        case .none, .custom:
            XCTAssertEqual(writeCount, 0)
        case .directory, .header:
            XCTAssertEqual(writeCount, 1)
        }
    }

    private func expectedContent(for moduleMap: ModuleMap) -> String? {
        let expectedContent: String
        switch moduleMap {
        case .none, .custom:
            return nil
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
        return expectedContent
    }
}
