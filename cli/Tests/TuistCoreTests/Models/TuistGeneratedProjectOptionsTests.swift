import FileSystem
import Foundation
import Path
import Testing
import TuistCore
import TuistSupport

@testable import TuistCore

struct TuistGeneratedProjectOptionsTests {
    private let fileSystem = FileSystem()

    @Test func withWorkspaceName_adds_clonedSourcePackagesDirPath_arguments() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let clonedSourcePackagesDirPath = temporaryDirectory.appending(component: "SourcePackages")
            let generationOptions = TuistGeneratedProjectOptions.GenerationOptions(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: ["-verbose"],
                staticSideEffectsWarningTargets: .all,
                enforceExplicitDependencies: false,
                defaultConfiguration: nil,
                optionalAuthentication: false,
                buildInsightsDisabled: false,
                testInsightsDisabled: false,
                disableSandbox: true,
                includeGenerateScheme: false
            )

            // When
            let result = generationOptions.withWorkspaceName("MyApp.xcworkspace")

            // Then
            let expectedPath = "\(clonedSourcePackagesDirPath.pathString)/MyApp"
            #expect(result.additionalPackageResolutionArguments.contains("-verbose"))
            #expect(result.additionalPackageResolutionArguments.contains("-clonedSourcePackagesDirPath"))
            #expect(result.additionalPackageResolutionArguments.contains(expectedPath))

            // Check that original arguments are preserved
            let arguments = result.additionalPackageResolutionArguments
            let clonedDirIndex = arguments.firstIndex(of: "-clonedSourcePackagesDirPath")!
            #expect(arguments[clonedDirIndex + 1] == expectedPath)
        }
    }

    @Test func withWorkspaceName_strips_xcworkspace_extension() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let clonedSourcePackagesDirPath = temporaryDirectory.appending(component: "SourcePackages")
            let generationOptions = TuistGeneratedProjectOptions.GenerationOptions(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: [],
                staticSideEffectsWarningTargets: .all,
                enforceExplicitDependencies: false,
                defaultConfiguration: nil,
                optionalAuthentication: false,
                buildInsightsDisabled: false,
                testInsightsDisabled: false,
                disableSandbox: false,
                includeGenerateScheme: false
            )

            // When
            let result = generationOptions.withWorkspaceName("MyComplexApp.xcworkspace")

            // Then
            let expectedPath = "\(clonedSourcePackagesDirPath.pathString)/MyComplexApp"
            #expect(result.additionalPackageResolutionArguments.contains(expectedPath))
        }
    }

    @Test func withWorkspaceName_without_clonedSourcePackagesDirPath_does_not_add_arguments() async throws {
        // Given
        let generationOptions = TuistGeneratedProjectOptions.GenerationOptions(
            resolveDependenciesWithSystemScm: false,
            disablePackageVersionLocking: false,
            clonedSourcePackagesDirPath: nil,
            additionalPackageResolutionArguments: ["-verbose"],
            staticSideEffectsWarningTargets: .all,
            enforceExplicitDependencies: false,
            defaultConfiguration: nil,
            optionalAuthentication: false,
            buildInsightsDisabled: false,
            testInsightsDisabled: false,
            disableSandbox: false,
            includeGenerateScheme: false
        )

        // When
        let result = generationOptions.withWorkspaceName("MyApp.xcworkspace")

        // Then
        #expect(result.additionalPackageResolutionArguments == ["-verbose"])
        #expect(!result.additionalPackageResolutionArguments.contains("-clonedSourcePackagesDirPath"))
    }

    @Test func withWorkspaceName_preserves_all_original_properties() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let clonedSourcePackagesDirPath = temporaryDirectory.appending(component: "SourcePackages")
            let originalOptions = TuistGeneratedProjectOptions.GenerationOptions(
                resolveDependenciesWithSystemScm: true,
                disablePackageVersionLocking: true,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: ["-verbose", "-configuration", "debug"],
                staticSideEffectsWarningTargets: .excluding(["TestTarget"]),
                enforceExplicitDependencies: true,
                defaultConfiguration: "Release",
                optionalAuthentication: true,
                buildInsightsDisabled: true,
                testInsightsDisabled: false,
                disableSandbox: true,
                includeGenerateScheme: true
            )

            // When
            let result = originalOptions.withWorkspaceName("MyApp.xcworkspace")

            // Then - all original properties should be preserved
            #expect(result.resolveDependenciesWithSystemScm == true)
            #expect(result.disablePackageVersionLocking == true)
            #expect(result.clonedSourcePackagesDirPath == clonedSourcePackagesDirPath)
            #expect(result.staticSideEffectsWarningTargets == .excluding(["TestTarget"]))
            #expect(result.enforceExplicitDependencies == true)
            #expect(result.defaultConfiguration == "Release")
            #expect(result.optionalAuthentication == true)
            #expect(result.buildInsightsDisabled == true)
            #expect(result.disableSandbox == true)
            #expect(result.includeGenerateScheme == true)

            // Original arguments should be preserved plus new ones
            #expect(result.additionalPackageResolutionArguments.contains("-verbose"))
            #expect(result.additionalPackageResolutionArguments.contains("-configuration"))
            #expect(result.additionalPackageResolutionArguments.contains("debug"))
            #expect(result.additionalPackageResolutionArguments.contains("-clonedSourcePackagesDirPath"))
        }
    }

    @Test func withWorkspaceName_handles_workspace_names_without_extension() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let clonedSourcePackagesDirPath = temporaryDirectory.appending(component: "SourcePackages")
            let generationOptions = TuistGeneratedProjectOptions.GenerationOptions(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: [],
                staticSideEffectsWarningTargets: .all,
                enforceExplicitDependencies: false,
                defaultConfiguration: nil,
                optionalAuthentication: false,
                buildInsightsDisabled: false,
                testInsightsDisabled: false,
                disableSandbox: false,
                includeGenerateScheme: false
            )

            // When
            let result = generationOptions.withWorkspaceName("MyApp")

            // Then
            let expectedPath = "\(clonedSourcePackagesDirPath.pathString)/MyApp"
            #expect(result.additionalPackageResolutionArguments.contains(expectedPath))
        }
    }
}
