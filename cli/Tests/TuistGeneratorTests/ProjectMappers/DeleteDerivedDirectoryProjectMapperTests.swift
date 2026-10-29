import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistConstants
import TuistCore
import XcodeGraph
@testable import TuistGenerator

struct DeleteDerivedDirectoryProjectMapperTests {
    @Test(.inTemporaryDirectory) func regeneration_preservesGeneratedTestPlanCoverage() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let planPath = projectPath.appending(components: "Derived", "TestPlans", "UnitTests.xctestplan")
        let descriptor = TestPlanDescriptor(path: planPath, testTargets: [], coverage: true)
        let executor = SideEffectDescriptorExecutor()
        let fileSystem = FileSystem()

        for _ in 0 ..< 2 {
            let (_, cleanup) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))
            try await executor.execute(sideEffects: [.testPlan(descriptor)])
            try await executor.execute(sideEffects: cleanup)

            let data = try await fileSystem.readFile(at: planPath)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let options = try #require(json["defaultOptions"] as? [String: Any])
            #expect(options["codeCoverage"] is [String: Any])
        }
    }

    @Test(.inTemporaryDirectory) func map_preservesGeneratedInputsDuringEarlyCleanup() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let fileSystem = FileSystem()
        let preservedDirectories = [
            Constants.DerivedDirectory.moduleMaps,
            Constants.DerivedDirectory.frameworkSearchPaths,
            Constants.DerivedDirectory.tuistCacheDebugging,
            Constants.DerivedDirectory.sources,
            Constants.DerivedDirectory.infoPlists,
            Constants.DerivedDirectory.entitlements,
        ]
        for directory in preservedDirectories {
            try await fileSystem.makeDirectory(at: derivedDirectory.appending(component: directory))
        }
        try await fileSystem.touch(derivedDirectory.appending(component: "TargetA.modulemap"))
        let obsoleteDirectory = derivedDirectory.appending(component: "Obsolete")
        try await fileSystem.makeDirectory(at: obsoleteDirectory)
        let obsoleteFile = derivedDirectory.appending(component: "obsolete.txt")
        try await fileSystem.touch(obsoleteFile)

        let (_, sideEffects) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))

        #expect(sideEffects.count == 2)
        #expect(sideEffects.contains(.directory(.init(path: obsoleteDirectory, state: .absent))))
        #expect(sideEffects.contains(.file(.init(path: obsoleteFile, state: .absent))))
    }

    @Test(.inTemporaryDirectory, arguments: ["Sources", "InfoPlists", "Entitlements", "TuistCacheDebugging"], [false, true])
    func map_unlinksPreservedDirectorySymlinks(directoryName: String, destinationExists: Bool) async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let link = derivedDirectory.appending(component: directoryName)
        let destination = projectPath.appending(component: "External")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: derivedDirectory)
        if destinationExists {
            try await fileSystem.makeDirectory(at: destination)
        }
        try await fileSystem.createSymbolicLink(from: link, to: destination)

        let (_, sideEffects) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))

        #expect(sideEffects == [.symbolicLink(.init(path: link, destination: destination, state: .absent))])
        #expect(try await fileSystem.contentsOfDirectory(derivedDirectory).contains(link))
    }

    @Test(.inTemporaryDirectory) func map_withoutDerivedDirectoryHasNoSideEffects() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        let (_, sideEffects) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))

        #expect(sideEffects.isEmpty)
    }
}
