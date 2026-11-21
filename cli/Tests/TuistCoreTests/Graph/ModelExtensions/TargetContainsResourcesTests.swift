import Path
import Testing
import XcodeGraph

@testable import TuistCore
@testable import TuistTesting

struct TargetContainsResourcesTests {
    private let folderPath: AbsolutePath = "/Project/Generated"

    @Test func containsResources_whenFolderDeclaresSources_ignoresResourceFiles() {
        let target = Target.test(buildableFolders: [
            BuildableFolder(
                path: folderPath,
                exceptions: [],
                resolvedFiles: [BuildableFolderFile(path: folderPath.appending(component: "Image.png"), compilerFlags: nil)],
                contents: [.sources]
            ),
        ])

        #expect(target.containsResources == false)
    }

    @Test func containsResources_whenEmptyFolderDeclaresResources() {
        let target = Target.test(buildableFolders: [
            BuildableFolder(path: folderPath, exceptions: [], resolvedFiles: [], contents: [.resources]),
        ])

        #expect(target.containsResources == true)
    }
}
