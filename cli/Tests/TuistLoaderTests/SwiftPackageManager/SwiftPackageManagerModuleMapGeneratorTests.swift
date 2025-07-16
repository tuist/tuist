import Mockable
import Path
import TuistCore
import TuistTesting
import XCTest

@testable import TuistLoader

final class SwiftPackageManagerModuleMapGeneratorTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerModuleMapGenerator!
    private var contentHasher: MockContentHashing!
    private var packageDirectory: AbsolutePath!
    private var publicHeadersPath: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        contentHasher = MockContentHashing()
        subject = SwiftPackageManagerModuleMapGenerator(contentHasher: contentHasher)

        packageDirectory = try temporaryPath()
            .appending(component: "PackageDir")
        publicHeadersPath = try temporaryPath()
            .appending(
                components: [
                    "Public",
                    "Headers",
                    "Path",
                ]
            )

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 }
    }

    override func tearDown() {
        contentHasher = nil
        subject = nil
        packageDirectory = nil
        publicHeadersPath = nil
        super.tearDown()
    }

    func test_generate_when_no_headers() async throws {
        try await test_generate(for: .none)
    }

    func test_generate_when_custom_module_map() async throws {
        try await test_generate(for: .custom(publicHeadersPath.appending(component: "module.modulemap"), umbrellaHeaderPath: nil))
    }

    func test_generate_when_umbrella_header() async throws {
        try await test_generate(
            for: .header(
                publicHeadersPath.appending(component: "Module.h"),
                moduleMapPath: packageDirectory.appending(components: "Derived", "Module.modulemap")
            )
        )
    }

    func test_generate_when_nested_umbrella_header() async throws {
        try await test_generate(
            for: .header(
                publicHeadersPath.appending(components: "Module", "Module.h"),
                moduleMapPath: packageDirectory.appending(components: "Derived", "Module.modulemap")
            )
        )
    }

    private func test_generate(for moduleMap: ModuleMap) async throws {
        var writeCount = 0

        try await fileSystem.makeDirectory(at: publicHeadersPath)
        try await fileSystem.makeDirectory(at: packageDirectory.appending(component: "Derived"))
        switch moduleMap {
        case .none:
            break
        case let .custom(moduleMapPath, umbrellaHeaderPath: umbrellaHeaderPath):
            try await fileSystem.touch(moduleMapPath)
            if let umbrellaHeaderPath {
                try await fileSystem.makeDirectory(at: umbrellaHeaderPath.parentDirectory)
                try await fileSystem.touch(umbrellaHeaderPath)
            }
        case let .header(
            umbrellaHeaderPath,
            moduleMapPath: moduleMapPath
        ):
            if try await !fileSystem.exists(umbrellaHeaderPath.parentDirectory) {
                try await fileSystem.makeDirectory(at: umbrellaHeaderPath.parentDirectory)
            }
            try await fileSystem.touch(umbrellaHeaderPath)
            try await fileSystem.touch(moduleMapPath)
        case let .directory(moduleMapPath: moduleMapPath, umbrellaDirectory: umbrellaDirectory):
            try await fileSystem.touch(moduleMapPath)
            try await fileSystem.makeDirectory(at: umbrellaDirectory)
        }
        fileHandler.stubWrite = { content, path, atomically in
            writeCount += 1
            guard let expectedContent = self.expectedContent(for: moduleMap) else {
                XCTFail("FileHandler.write should not be called")
                return
            }

            XCTAssertEqual(content, expectedContent)
            XCTAssertEqual(
                path,
                self.packageDirectory.appending(components: "Derived", "Module.modulemap")
            )
            XCTAssertTrue(atomically)
        }

        var hash: String? = nil

        given(contentHasher)
            .hash(path: .any)
            .willProduce { hash ?? $0.pathString }

        let got = try await subject.generate(
            packageDirectory: packageDirectory,
            moduleName: "Module",
            publicHeadersPath: publicHeadersPath
        )

        // Set hasher for path on disk
        hash = expectedContent(for: moduleMap)

        // generate a 2nd time to validate that we dont write content that is already on disk
        _ = try await subject.generate(
            packageDirectory: packageDirectory,
            moduleName: "Module",
            publicHeadersPath: publicHeadersPath
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
                  umbrella header "\(umbrellaHeaderPath.pathString)"

                  export *
                  module * { export * }
                }
                """
            } else {
                expectedContent = """
                framework module Module {
                  umbrella header "\(umbrellaHeaderPath.pathString)"

                  export *
                  module * { export * }
                }
                """
            }
        case let .directory(moduleMapPath: _, umbrellaDirectory: umbrellaDirectory):
            expectedContent = """
            module Module {
                umbrella "\(umbrellaDirectory.pathString)"
                export *
            }

            """
        }
        return expectedContent
    }
}
