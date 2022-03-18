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
        var templateStrings: [String] = []
        synthesizedResourceInterfacesGenerator.renderStub = { _, templateString, _, _, paths in
            templateStrings.append(templateString)
            let content = paths.map { $0.components.suffix(2).joined(separator: "/") }.joined(separator: ", ")
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
        let lottieFile = targetAPath.appending(component: "LottieAnimation.lottie")

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
        let lottieTemplatePath = projectPath.appending(component: "Lottie.stencil")
        try fileHandler.write("lottie template", path: lottieTemplatePath, atomically: true)
        try fileHandler.write("a", path: lottieFile, atomically: true)
        let stringsTemplatePath = projectPath.appending(component: "Strings.stencil")
        try fileHandler.write("strings template", path: stringsTemplatePath, atomically: true)

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
                .file(path: lottieFile),
            ]
        )

        let resourceSynthesizers: [ResourceSynthesizer] = [
            .init(
                parser: .assets,
                extensions: ["xcassets"],
                template: .defaultTemplate("Assets")
            ),
            .init(
                parser: .strings,
                extensions: ["strings", "stringsdict"],
                template: .file(stringsTemplatePath)
            ),
            .init(
                parser: .plists,
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
            .init(
                parser: .fonts,
                extensions: ["otf", "ttc", "ttf"],
                template: .defaultTemplate("Fonts")
            ),
            .init(
                parser: .json,
                extensions: ["lottie"],
                template: .file(lottieTemplatePath)
            ),
        ]

        let project = Project.test(
            path: projectPath,
            targets: [
                targetA,
            ],
            resourceSynthesizers: resourceSynthesizers
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
                        contents: "TargetA/a.xcassets".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Strings+TargetA.swift"),
                        contents: "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict"
                            .data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Plists+TargetA.swift"),
                        contents: "TargetA/Environment.plist".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Fonts+TargetA.swift"),
                        contents: "TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "Lottie+TargetA.swift"),
                        contents: "TargetA/LottieAnimation.lottie".data(using: .utf8)
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
                                contentHash: try contentHasher.hash("TargetA/a.xcassets".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Strings+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash(
                                    "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict".data(using: .utf8)!
                                )
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Plists+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("TargetA/Environment.plist".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Fonts+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher
                                    .hash("TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)!)
                            ),
                            SourceFile(
                                path: derivedSourcesPath
                                    .appending(component: "Lottie+TargetA.swift"),
                                compilerFlags: nil,
                                contentHash: try contentHasher.hash("TargetA/LottieAnimation.lottie".data(using: .utf8)!)
                            ),
                        ],
                        resources: targetA.resources
                    ),
                ],
                resourceSynthesizers: resourceSynthesizers
            )
        )
        XCTAssertEqual(
            templateStrings,
            [
                SynthesizedResourceInterfaceTemplates.assetsTemplate,
                "strings template",
                SynthesizedResourceInterfaceTemplates.plistsTemplate,
                SynthesizedResourceInterfaceTemplates.fontsTemplate,
                "lottie template",
            ]
        )

        XCTAssertPrinterContains(
            "Skipping synthesizing accessors for \(emptyPlist.pathString) because its contents are empty.",
            at: .warning,
            ==
        )
    }

    func testMap_whenDisableSynthesizedResourceAccessors() throws {
        // Given
        var templateStrings: [String] = []
        synthesizedResourceInterfacesGenerator.renderStub = { _, templateString, _, _, paths in
            templateStrings.append(templateString)
            let content = paths.map { $0.components.suffix(2).joined(separator: "/") }.joined(separator: ", ")
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
        let lottieFile = targetAPath.appending(component: "LottieAnimation.lottie")

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
        let lottieTemplatePath = projectPath.appending(component: "Lottie.stencil")
        try fileHandler.write("lottie template", path: lottieTemplatePath, atomically: true)
        try fileHandler.write("a", path: lottieFile, atomically: true)
        let stringsTemplatePath = projectPath.appending(component: "Strings.stencil")
        try fileHandler.write("strings template", path: stringsTemplatePath, atomically: true)

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
                .file(path: lottieFile),
            ]
        )

        let resourceSynthesizers: [ResourceSynthesizer] = [
            .init(
                parser: .assets,
                extensions: ["xcassets"],
                template: .defaultTemplate("Assets")
            ),
            .init(
                parser: .strings,
                extensions: ["strings", "stringsdict"],
                template: .file(stringsTemplatePath)
            ),
            .init(
                parser: .plists,
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
            .init(
                parser: .fonts,
                extensions: ["otf", "ttc", "ttf"],
                template: .defaultTemplate("Fonts")
            ),
            .init(
                parser: .json,
                extensions: ["lottie"],
                template: .file(lottieTemplatePath)
            ),
        ]

        let project = Project.test(
            path: projectPath,
            options: .test(
                disableSynthesizedResourceAccessors: true
            ),
            targets: [
                targetA,
            ],
            resourceSynthesizers: resourceSynthesizers
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(project, mappedProject)
        XCTAssertEqual(sideEffects, [])
    }

    func testMap_bundleName_whenBundleAccessorsAreEnabled() throws {
        // Given
        var bundleNames: [String?] = []
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, bundleName, _ in
            bundleNames.append(bundleName)
            return ""
        }
        let projectPath = try temporaryPath()
        let targetPath = projectPath.appending(component: "TargetA")
        let ttfFont = targetPath.appending(component: "ttfFont.ttf")
        try stub(file: ttfFont)

        let project: Project = .test(
            options: .test(
                disableBundleAccessors: false,
                disableSynthesizedResourceAccessors: false
            ),
            targets: [
                .test(
                    name: "TargetA",
                    resources: [
                        .file(path: ttfFont),
                    ]
                ),
            ],
            resourceSynthesizers: makeResourceSynthesizers()
        )

        // When
        _ = try subject.map(project: project)

        // Then
        XCTAssertEqual(bundleNames, [
            "Bundle.module",
        ])
    }

    func testMap_bundleName_whenBundleAccessorsAreDisabled() throws {
        // Given
        var bundleNames: [String?] = []
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, bundleName, _ in
            bundleNames.append(bundleName)
            return ""
        }
        let projectPath = try temporaryPath()
        let targetPath = projectPath.appending(component: "TargetA")
        let ttfFont = targetPath.appending(component: "ttfFont.ttf")
        try stub(file: ttfFont)

        let project: Project = .test(
            options: .test(
                disableBundleAccessors: true,
                disableSynthesizedResourceAccessors: false
            ),
            targets: [
                .test(
                    name: "TargetA",
                    resources: [
                        .file(path: ttfFont),
                    ]
                ),
            ],
            resourceSynthesizers: makeResourceSynthesizers()
        )

        // When
        _ = try subject.map(project: project)

        // Then
        XCTAssertEqual(bundleNames, [
            nil,
        ])
    }

    // MARK: - Helpers

    private func stub(file: AbsolutePath) throws {
        try fileHandler.touch(file)
        try fileHandler.write("a", path: file, atomically: true)
    }

    private func makeResourceSynthesizers() -> [ResourceSynthesizer] {
        [
            .init(
                parser: .assets,
                extensions: ["xcassets"],
                template: .defaultTemplate("Assets")
            ),
            .init(
                parser: .plists,
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
            .init(
                parser: .fonts,
                extensions: ["otf", "ttc", "ttf"],
                template: .defaultTemplate("Fonts")
            ),
        ]
    }
}
