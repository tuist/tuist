import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class SynthesizedResourceInterfaceProjectMapperTests: TuistUnitTestCase {
    private var subject: SynthesizedResourceInterfaceProjectMapper!
    private var synthesizedResourceInterfacesGenerator: MockSynthesizedResourceInterfaceGenerator!
    private var contentHasher: ContentHashing!

    override func setUp() {
        super.setUp()

        synthesizedResourceInterfacesGenerator = MockSynthesizedResourceInterfaceGenerator()
        contentHasher = ContentHasher()
        subject = SynthesizedResourceInterfaceProjectMapper(
            synthesizedResourceInterfacesGenerator: synthesizedResourceInterfacesGenerator,
            contentHasher: contentHasher
        )
    }

    override func tearDown() {
        contentHasher = nil
        synthesizedResourceInterfacesGenerator = nil
        subject = nil
        super.tearDown()
    }

    func test_map() throws {
        // Given
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, paths in
            let content = paths.map(\.basename).joined(separator: ", ")
            return content
        }

        let projectPath = try temporaryPath()
        let targetAPath = projectPath.appending(component: "TargetA")
        let aAssets = targetAPath.appending(component: "a.xcassets")
        let aAsset = aAssets.appending(component: "asset")
        let frenchStrings = targetAPath.appending(components: "fr.lproj", "aStrings.strings")
        let frenchStringsDict = targetAPath.appending(components: "fr.lproj", "aStrings.stringsdict")
        let englishStrings = targetAPath.appending(components: "en.lproj", "aStrings.strings")
        let englishStringsDict = targetAPath.appending(components: "en.lproj", "aStrings.stringsdict")
        let environmentPlist = targetAPath.appending(component: "Environment.plist")
        let emptyPlist = targetAPath.appending(component: "Empty.plist")
        let ttfFont = targetAPath.appending(component: "ttfFont.ttf")
        let otfFont = targetAPath.appending(component: "otfFont.otf")
        let ttcFont = targetAPath.appending(component: "ttcFont.ttc")

        try fileHandler.createFolder(aAssets)
        try fileHandler.touch(aAsset)
        try fileHandler.touch(frenchStrings)
        try fileHandler.touch(frenchStringsDict)
        try fileHandler.touch(englishStrings)
        try fileHandler.touch(englishStringsDict)
        try fileHandler.write("a", path: frenchStrings, atomically: true)
        try fileHandler.write("a", path: frenchStringsDict, atomically: true)
        try fileHandler.write("a", path: englishStrings, atomically: true)
        try fileHandler.write("a", path: englishStringsDict, atomically: true)
        try fileHandler.touch(emptyPlist)
        try fileHandler.write("a", path: environmentPlist, atomically: true)
        try fileHandler.write("a", path: ttfFont, atomically: true)
        try fileHandler.write("a", path: otfFont, atomically: true)
        try fileHandler.write("a", path: ttcFont, atomically: true)

        let targetA = Target.test(
            name: "TargetA",
            resources: [
                .folderReference(path: aAssets),
                .file(path: frenchStrings),
                .file(path: frenchStringsDict),
                .file(path: englishStrings),
                .file(path: englishStringsDict),
                .file(path: emptyPlist),
                .file(path: environmentPlist),
                .file(path: ttfFont),
                .file(path: otfFont),
                .file(path: ttcFont),
            ]
        )

        let project = Project.test(
            path: projectPath,
            targets: [
                targetA,
            ]
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        let derivedPath = projectPath
            .appending(component: Constants.DerivedDirectory.name)
        let derivedSourcesPath = derivedPath
            .appending(component: Constants.DerivedDirectory.sources)
        XCTAssertEqual(
            sideEffects,
            [
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Assets+TargetA.swift"),
                        contents: "a.xcassets".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Strings+TargetA.swift"),
                        contents: "aStrings.strings, aStrings.stringsdict".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Environment.swift"),
                        contents: "Environment.plist".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Fonts+TargetA.swift"),
                        contents: "ttfFont.ttf, otfFont.otf, ttcFont.ttc".data(using: .utf8)
                    )
                ),
            ]
        )
        XCTAssertEqual(
            mappedProject,
            Project.test(
                path: projectPath,
                targets: [
                    Target.test(
                        name: targetA.name,
                        sources: [
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Assets+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("a.xcassets".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Strings+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("aStrings.strings, aStrings.stringsdict".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Environment.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("Environment.plist".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Fonts+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("ttfFont.ttf, otfFont.otf, ttcFont.ttc".data(using: .utf8)!)
                            ),
                        ],
                        resources: targetA.resources
                    ),
                ]
            )
        )

        XCTAssertPrinterContains(
            "Skipping synthesizing accessors for \(emptyPlist.pathString) because its contents are empty.",
            at: .warning,
            ==
        )
    }
}
