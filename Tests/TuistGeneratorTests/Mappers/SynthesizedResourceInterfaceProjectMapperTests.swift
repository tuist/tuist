import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class SynthesizedResourceInterfaceProjectMapperTests: TuistUnitTestCase {
    private var subject: SynthesizedResourceInterfaceProjectMapper!
    private var synthesizedResourceInterfacesGenerator: MockSynthesizedResourceInterfaceGenerator!

    override func setUp() {
        super.setUp()

        synthesizedResourceInterfacesGenerator = MockSynthesizedResourceInterfaceGenerator()
        subject = SynthesizedResourceInterfaceProjectMapper(
            synthesizedResourceInterfacesGenerator: synthesizedResourceInterfacesGenerator
        )
    }

    override func tearDown() {
        super.tearDown()

        synthesizedResourceInterfacesGenerator = nil
        subject = nil
    }

    func test_map() throws {
        // Given
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _ in
            ""
        }

        let projectPath = try temporaryPath()
        let targetAPath = projectPath.appending(component: "TargetA")
        let aAssets = targetAPath.appending(component: "a.xcassets")
        let aAsset = aAssets.appending(component: "asset")
        let frenchStrings = targetAPath.appending(components: "fr.lproj", "aStrings.strings")
        let englishStrings = targetAPath.appending(components: "en.lproj", "aStrings.strings")
        let environmentPlist = targetAPath.appending(component: "Environment.plist")
        let emptyPlist = targetAPath.appending(component: "Empty.plist")
        let ttfFont = targetAPath.appending(component: "ttfFont.ttf")
        let otfFont = targetAPath.appending(component: "otfFont.otf")
        let ttcFont = targetAPath.appending(component: "ttcFont.ttc")

        try fileHandler.createFolder(aAssets)
        try fileHandler.touch(aAsset)
        try fileHandler.touch(frenchStrings)
        try fileHandler.touch(englishStrings)
        try fileHandler.write("a", path: frenchStrings, atomically: true)
        try fileHandler.write("a", path: englishStrings, atomically: true)
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
                .file(path: englishStrings),
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
                        contents: "".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Strings+TargetA.swift"),
                        contents: "".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Environment.swift"),
                        contents: "".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Fonts+TargetA.swift"),
                        contents: "".data(using: .utf8)
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
                            (path: derivedSourcesPath
                                .appending(component: "Assets+TargetA.swift"),
                                compilerFlags: nil),
                            (path: derivedSourcesPath
                                .appending(component: "Strings+TargetA.swift"),
                                compilerFlags: nil),
                            (path: derivedSourcesPath
                                .appending(component: "Environment.swift"),
                                compilerFlags: nil),
                            (path: derivedSourcesPath
                                .appending(component: "Fonts+TargetA.swift"),
                                compilerFlags: nil),
                        ],
                        resources: targetA.resources
                    ),
                ]
            )
        )
        
        XCTAssertPrinterContains(
            "Skipping synthesizing accessors for \(emptyPlist.pathString) because it's contents are empty.",
            at: .notice,
            ==
        )
    }
}
