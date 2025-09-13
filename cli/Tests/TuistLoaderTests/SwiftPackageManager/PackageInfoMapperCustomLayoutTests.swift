import FileSystem
import FileSystemTesting
import Mockable
import Path
import ProjectDescription
import Testing
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistLoader
@testable import TuistTesting

struct PackageInfoMapperCustomLayoutTests {
    private var subject: PackageInfoMapper!
    private let fileSystem = FileSystem()

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.9")
        subject = PackageInfoMapper()
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSourcesDirectlyInSourcesDirectory_SE0162Support() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcesPath = packagePath.appending(try RelativePath(validating: "Sources"))
        
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.touch(sourcesPath.appending(component: "Target1.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "Helper.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "Utils.swift"))
        
        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        
        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:]
        )
        
        #expect(project != nil)
        #expect(project?.targets.count == 1)
        
        let target = project?.targets.first
        #expect(target?.name == "Target1")
        
        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/**") == true)
    }
    
    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenStandardLayout_stillWorks() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let targetPath = packagePath.appending(try RelativePath(validating: "Sources/Target1"))
        
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.touch(targetPath.appending(component: "Target1.swift"))
        
        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )
        
        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:]
        )
        
        #expect(project != nil)
        #expect(project?.targets.count == 1)
        
        let target = project?.targets.first
        #expect(target?.name == "Target1")
        
        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/Target1/**") == true)
    }
    
    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNoSourcesFound_throwsError() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        
        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )
        
        await #expect(throws: PackageInfoMapperError.self) {
            _ = try await subject.map(
                packageInfo: packageInfo,
                path: packagePath,
                packageType: .local,
                packageSettings: .test(),
                packageModuleAliases: [:]
            )
        }
    }
    
    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenMixedCAndSwiftSources_detectsProperly() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcesPath = packagePath.appending(try RelativePath(validating: "Sources"))
        
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.touch(sourcesPath.appending(component: "main.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "helper.c"))
        try await fileSystem.touch(sourcesPath.appending(component: "helper.h"))
        
        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )
        
        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:]
        )
        
        #expect(project != nil)
        let target = project?.targets.first
        #expect(target?.name == "Target1")
        
        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/**") == true)
    }
}
