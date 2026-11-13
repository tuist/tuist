import ArgumentParser
import Testing
@testable import TuistCore
@testable import TuistKit
@testable import TuistTesting

struct CleanCommandTests {
    @Test(.withMockedEnvironment()) func categoriesToCleanDefaultsToAllCategories() throws {
        let cleanCommand = try CleanCommand.parse([])

        #expect(cleanCommand.categoriesToClean == TuistCleanCategory.allCases)
    }

    @Test(.withMockedEnvironment()) func categoriesToCleanAllowsCategoriesWithoutExclusions() throws {
        let cleanCommand = try CleanCommand.parse([
            "dependencies", "manifests",
        ])

        #expect(cleanCommand.categoriesToClean == [
            TuistCleanCategory.dependencies,
            TuistCleanCategory.global(.manifests),
        ])
    }

    @Test(.withMockedEnvironment()) func categoriesToCleanExcludesCategories() throws {
        let cleanCommand = try CleanCommand.parse([
            "--exclude", "dependencies", "manifests",
        ])
        let expectedCategories = TuistCleanCategory.allCases.filter {
            $0 != .dependencies && $0 != .global(.manifests)
        }

        #expect(cleanCommand.categoriesToClean == expectedCategories)
    }

    @Test(.withMockedEnvironment()) func categoriesToCleanExcludesCategoriesWithShortOption() throws {
        let cleanCommand = try CleanCommand.parse([
            "-e", "dependencies",
        ])
        let expectedCategories = TuistCleanCategory.allCases.filter {
            $0 != .dependencies
        }

        #expect(cleanCommand.categoriesToClean == expectedCategories)
    }

    @Test(.withMockedEnvironment()) func validateFailsWhenCategoriesAndExclusionsAreCombined() throws {
        do {
            _ = try CleanCommand.parse([
                "dependencies", "manifests",
                "--exclude", "dependencies",
            ])
            Issue.record("Expected parsing to fail when category arguments and --exclude are used together")
        } catch {
            #expect(CleanCommand.message(for: error) == "Cannot use category arguments and --exclude at the same time.")
        }
    }
}
