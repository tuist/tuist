import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistTesting

struct TargetCoreTests {
    @Test func target_with_resources_only() {
        let target = Target.test(
            product: .staticFramework,
            resources: .init([.file(path: "/path/to/Asset.png")])
        )

        #expect(target.containsResources == true)
        #expect(target.buildableFoldersContainResources == false)
        #expect(target.buildableFoldersContainSources == false)
    }

    @Test func target_with_coreDataModels_only() {
        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            coreDataModels: [CoreDataModel(path: "/path/to/Model.xcdatamodeld", versions: [], currentVersion: "1")]
        )

        #expect(target.containsResources == true)
        #expect(target.buildableFoldersContainResources == false)
        #expect(target.buildableFoldersContainSources == false)
    }

    @Test func target_with_no_resources_or_buildable_folders() {
        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            buildableFolders: []
        )

        #expect(target.containsResources == false)
        #expect(target.buildableFoldersContainResources == false)
        #expect(target.buildableFoldersContainSources == false)
    }

    @Test func target_with_buildable_folder_resources_only() throws {
        let folderPath = try AbsolutePath(validating: "/sources")

        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            buildableFolders: [
                BuildableFolder(
                    path: folderPath,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [
                        BuildableFolderFile(path: folderPath.appending(component: "data.json"), compilerFlags: nil),
                    ]
                ),
            ]
        )

        #expect(target.containsResources == true)
        #expect(target.buildableFoldersContainResources == true)
        #expect(target.buildableFoldersContainSources == false)
    }

    @Test func target_with_buildable_folder_sources_only() throws {
        let folderPath = try AbsolutePath(validating: "/sources")

        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            buildableFolders: [
                BuildableFolder(
                    path: folderPath,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [
                        BuildableFolderFile(path: folderPath.appending(component: "File.swift"), compilerFlags: nil),
                    ]
                ),
            ]
        )

        #expect(target.containsResources == false)
        #expect(target.buildableFoldersContainResources == false)
        #expect(target.buildableFoldersContainSources == true)
    }

    @Test func target_with_buildable_folder_sources_and_resources() throws {
        let folderPath = try AbsolutePath(validating: "/sources")

        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            buildableFolders: [
                BuildableFolder(
                    path: folderPath,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [
                        BuildableFolderFile(path: folderPath.appending(component: "File.swift"), compilerFlags: nil),
                        BuildableFolderFile(path: folderPath.appending(component: "data.json"), compilerFlags: nil),
                    ]
                ),
            ]
        )

        #expect(target.containsResources == true)
        #expect(target.buildableFoldersContainResources == true)
        #expect(target.buildableFoldersContainSources == true)
    }

    @Test(arguments: ["txt", "json", "js", "md", "strings", "plist", "storyboard", "xib", "xcassets", "scnassets", "bundle"])
    func target_with_buildable_folder_resource_extension(resourceExtension: String) throws {
        let folderPath = try AbsolutePath(validating: "/sources")

        let target = Target.test(
            product: .staticFramework,
            resources: .init([]),
            buildableFolders: [
                BuildableFolder(
                    path: folderPath,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [
                        BuildableFolderFile(path: folderPath.appending(component: "file.\(resourceExtension)"), compilerFlags: nil),
                    ]
                ),
            ]
        )

        #expect(target.containsResources == true)
        #expect(target.buildableFoldersContainResources == true)
        #expect(target.buildableFoldersContainSources == false)
    }
}
