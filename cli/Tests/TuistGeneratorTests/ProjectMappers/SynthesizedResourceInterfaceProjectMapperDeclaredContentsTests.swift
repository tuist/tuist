import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistCore
import TuistThreadSafe
import XcodeGraph

@testable import TuistGenerator
@testable import TuistTesting

struct SynthesizedResourceInterfaceProjectMapperDeclaredContentsTests {
    @Test(.inTemporaryDirectory) func map_skipsFoldersThatDeclareContents() async throws {
        // Given
        let generator = MockSynthesizedResourceInterfaceGenerator()
        let plistNames = ThreadSafe<[String]>([])
        generator.renderStub = { _, _, _, _, _, paths in
            plistNames.mutate { $0.append(contentsOf: paths.map(\.basename)) }
            return ""
        }
        let subject = SynthesizedResourceInterfaceProjectMapper(
            synthesizedResourceInterfacesGenerator: generator,
            contentHasher: ContentHasher()
        )
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let declaredPlist = projectPath.appending(components: "Generated", "Declared.plist")
        let scannedPlist = projectPath.appending(components: "Resources", "Scanned.plist")
        let plistData = try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .xml, options: 0)
        for plist in [declaredPlist, scannedPlist] {
            try await FileSystem().makeDirectory(at: plist.parentDirectory)
            try plistData.write(to: URL(fileURLWithPath: plist.pathString))
        }
        let target = Target.test(
            name: "TargetA",
            buildableFolders: [
                BuildableFolder(
                    path: declaredPlist.parentDirectory,
                    exceptions: [],
                    resolvedFiles: [BuildableFolderFile(path: declaredPlist, compilerFlags: nil)],
                    contents: [.resources]
                ),
                BuildableFolder(
                    path: scannedPlist.parentDirectory,
                    exceptions: [],
                    resolvedFiles: [BuildableFolderFile(path: scannedPlist, compilerFlags: nil)]
                ),
            ]
        )
        let project = Project.test(
            path: projectPath,
            targets: [target],
            resourceSynthesizers: [
                .init(parser: .plists, parserOptions: [:], extensions: ["plist"], template: .defaultTemplate("Plists")),
            ]
        )

        // When
        _ = try await subject.map(project: project)

        // Then
        #expect(plistNames.value == ["Scanned.plist"])
    }
}
