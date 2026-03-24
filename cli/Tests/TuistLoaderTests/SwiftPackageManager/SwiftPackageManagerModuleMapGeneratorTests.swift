import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting

@testable import TuistLoader

struct SwiftPackageManagerModuleMapGeneratorTests {
    private let subject: SwiftPackageManagerModuleMapGenerator
    private let contentHasher: MockContentHashing
    private let packageDirectory: AbsolutePath
    private let publicHeadersPath: AbsolutePath
    private let fileSystem = FileSystem()
    private let fileHandler = FileHandler.shared

    init() throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        contentHasher = MockContentHashing()
        subject = SwiftPackageManagerModuleMapGenerator(contentHasher: contentHasher)
        packageDirectory = temporaryPath.appending(component: "PackageDir")
        publicHeadersPath = temporaryPath.appending(components: ["Public", "Headers", "Path"])

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 }
    }

    @Test(.inTemporaryDirectory) func generate_when_no_headers() async throws {
        try await test_generate(for: .none)
    }

    @Test(.inTemporaryDirectory) func generate_when_custom_module_map() async throws {
        try await test_generate(for: .custom(publicHeadersPath.appending(component: "module.modulemap"), umbrellaHeaderPath: nil))
    }

    @Test(.inTemporaryDirectory) func generate_when_umbrella_header() async throws {
        try await test_generate(
            for: .header(
                publicHeadersPath.appending(component: "Module.h"),
                moduleMapPath: packageDirectory.appending(components: "Derived", "Module.modulemap")
            )
        )
    }

    @Test(.inTemporaryDirectory) func generate_when_nested_umbrella_header() async throws {
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
        case let .header(umbrellaHeaderPath, moduleMapPath: moduleMapPath):
            if try await !fileSystem.exists(umbrellaHeaderPath.parentDirectory) {
                try await fileSystem.makeDirectory(at: umbrellaHeaderPath.parentDirectory)
            }
            try await fileSystem.touch(umbrellaHeaderPath)
            try await fileSystem.touch(moduleMapPath)
        case let .directory(moduleMapPath: moduleMapPath, umbrellaDirectory: umbrellaDirectory):
            try await fileSystem.touch(moduleMapPath)
            try await fileSystem.makeDirectory(at: umbrellaDirectory)
        }

        var hash: String?
        given(contentHasher)
            .hash(path: .any)
            .willProduce { hash ?? $0.pathString }

        let got = try await subject.generate(
            packageDirectory: packageDirectory,
            moduleName: "Module",
            publicHeadersPath: publicHeadersPath
        )

        hash = expectedContent(for: moduleMap)

        _ = try await subject.generate(
            packageDirectory: packageDirectory,
            moduleName: "Module",
            publicHeadersPath: publicHeadersPath
        )

        #expect(got == moduleMap)
    }

    private func expectedContent(for moduleMap: ModuleMap) -> String? {
        switch moduleMap {
        case .none, .custom:
            return nil
        case let .header(umbrellaHeaderPath, moduleMapPath: _):
            return """
            framework module Module {
              umbrella header "\(umbrellaHeaderPath.pathString)"

              export *
              module * { export * }
            }
            """
        case let .directory(moduleMapPath: _, umbrellaDirectory: umbrellaDirectory):
            return """
            module Module {
                umbrella "\(umbrellaDirectory.pathString)"
                export *
            }

            """
        }
    }
}
