import Foundation
import Path
import TuistConstants
import TuistCore
import TuistSupport
import TuistThreadSafe
import XcodeGraph
import XCTest

@testable import TuistGenerator
@testable import TuistTesting

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

    func test_map() async throws {
        try await withMockedDependencies {
            // Given
            let templateStrings = ThreadSafe<[String]>([])
            let parserOptionsStrings = ThreadSafe<[ResourceSynthesizer.Parser: String]>([:])
            synthesizedResourceInterfacesGenerator.renderStub = { parser, parserOptions, templateString, _, _, paths in
                templateStrings.mutate { $0.append(templateString) }
                let optionsString = parserOptions.map { "\($0.key): \($0.value.value)" }.sorted().joined(separator: ", ")
                parserOptionsStrings.mutate { $0[parser] = optionsString }
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
            let coreDataModelFolder = targetAPath.appending(component: "CoreDataModel.xcdatamodeld")
            let coreDataModelVersionFile = targetAPath.appending(
                components: "CoreDataModel.xcdatamodeld",
                "CoreDataModel.xcdatamodel"
            )

            try await fileSystem.makeDirectory(at:aAssets)
            try await fileSystem.touch(aAsset)
            try await fileSystem.touch(frenchStrings)
            try await fileSystem.touch(frenchStringsDict)
            try await fileSystem.touch(englishStrings)
            try await fileSystem.touch(englishStringsDict)
            try await fileSystem.touch(coreDataModelVersionFile)
            try await fileSystem.writeText("a", at: frenchStrings)
            try await fileSystem.writeText("a", at: frenchStringsDict)
            try await fileSystem.writeText("a", at: englishStrings)
            try await fileSystem.writeText("a", at: englishStringsDict)
            try await fileSystem.touch(emptyPlist)
            try await fileSystem.writeText("a", at: environmentPlist)
            try await fileSystem.writeText("a", at: ttfFont)
            try await fileSystem.writeText("a", at: otfFont)
            try await fileSystem.writeText("a", at: ttcFont)
            let lottieTemplatePath = projectPath.appending(component: "Lottie.stencil")
            try await fileSystem.writeText("lottie template", at: lottieTemplatePath)
            try await fileSystem.writeText("a", at: lottieFile)
            let stringsTemplatePath = projectPath.appending(component: "Strings.stencil")
            try await fileSystem.writeText("strings template", at: stringsTemplatePath)
            let coreDataTemplatePath = projectPath.appending(component: "CoreData.stencil")
            try await fileSystem.writeText("core data template", at: coreDataTemplatePath)
            try await fileSystem.makeDirectory(at:coreDataModelFolder)
            try await fileSystem.writeText("a", at: coreDataModelVersionFile)

            let targetA = Target.test(
                name: "TargetA",
                resources: .init(
                    [
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
                ),
                coreDataModels: [
                    CoreDataModel(
                        path: coreDataModelFolder,
                        versions: [
                            coreDataModelVersionFile,
                        ],
                        currentVersion: "CoreDataModel"
                    ),
                ]
            )

            let resourceSynthesizers: [ResourceSynthesizer] = [
                .init(
                    parser: .assets,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["xcassets"],
                    template: .defaultTemplate("Assets")
                ),
                .init(
                    parser: .strings,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["strings", "stringsdict"],
                    template: .file(stringsTemplatePath)
                ),
                .init(
                    parser: .plists,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["plist"],
                    template: .defaultTemplate("Plists")
                ),
                .init(
                    parser: .fonts,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["otf", "ttc", "ttf", "woff"],
                    template: .defaultTemplate("Fonts")
                ),
                .init(
                    parser: .json,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["lottie"],
                    template: .file(lottieTemplatePath)
                ),
                .init(
                    parser: .coreData,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["xcdatamodeld"],
                    template: .file(coreDataTemplatePath)
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
            let (mappedProject, sideEffects) = try await subject.map(project: project)

            // Then
            let derivedPath = projectPath
                .appending(component: Constants.DerivedDirectory.name)
            let derivedSourcesPath = derivedPath
                .appending(component: Constants.DerivedDirectory.sources)
            let expectedSideEffects: [SideEffectDescriptor] = [
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistAssets+TargetA.swift"),
                        contents: "TargetA/a.xcassets".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistStrings+TargetA.swift"),
                        contents: "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict"
                            .data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistPlists+TargetA.swift"),
                        contents: "TargetA/Environment.plist".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistFonts+TargetA.swift"),
                        contents: "TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistLottie+TargetA.swift"),
                        contents: "TargetA/LottieAnimation.lottie".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistCoreData+TargetA.swift"),
                        contents: "TargetA/CoreDataModel.xcdatamodeld".data(using: .utf8)
                    )
                ),
            ]
            XCTAssertEqual(
                Set(sideEffects.map(\.description)),
                Set(expectedSideEffects.map(\.description))
            )
            let expectedSources: [SourceFile] = [
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistAssets+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/a.xcassets".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistStrings+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash(
                        "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict".data(using: .utf8)!
                    )
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistPlists+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/Environment.plist".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistFonts+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher
                        .hash("TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistLottie+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/LottieAnimation.lottie".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistCoreData+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/CoreDataModel.xcdatamodeld".data(using: .utf8)!)
                ),
            ]
            let actualSources = mappedProject.targets[targetA.name]!.sources
                .sorted(by: { $0.path.pathString < $1.path.pathString })
            let sortedExpectedSources = expectedSources.sorted(by: { $0.path.pathString < $1.path.pathString })
            XCTAssertEqual(actualSources, sortedExpectedSources)
            // Check other properties are unchanged
            XCTAssertEqual(mappedProject.path, projectPath)
            XCTAssertEqual(mappedProject.targets.count, 1)
            XCTAssertEqual(mappedProject.targets[targetA.name]?.name, targetA.name)
            XCTAssertEqual(mappedProject.targets[targetA.name]?.resources, targetA.resources)
            XCTAssertEqual(mappedProject.targets[targetA.name]?.coreDataModels, targetA.coreDataModels)
            XCTAssertEqual(
                templateStrings.value.sorted(),
                [
                    SynthesizedResourceInterfaceTemplates.assetsTemplate,
                    "strings template",
                    SynthesizedResourceInterfaceTemplates.plistsTemplate,
                    SynthesizedResourceInterfaceTemplates.fontsTemplate,
                    "lottie template",
                    "core data template",
                ].sorted()
            )
            [
                ResourceSynthesizer.Parser.assets,
                ResourceSynthesizer.Parser.strings,
                ResourceSynthesizer.Parser.plists,
                ResourceSynthesizer.Parser.fonts,
                ResourceSynthesizer.Parser.json,
                ResourceSynthesizer.Parser.coreData,
            ].forEach { parser in
                XCTAssertEqual(
                    parserOptionsStrings.value[parser],
                    "boolValue: true, doubleValue: 1.0, intValue: 999, stringValue: test"
                )
            }
        }
    }

    func testMap_whenUseBuildableFolders() async throws {
        try await withMockedDependencies {
            // Given
            let templateStrings = ThreadSafe<[String]>([])
            let parserOptionsStrings = ThreadSafe<[ResourceSynthesizer.Parser: String]>([:])
            synthesizedResourceInterfacesGenerator.renderStub = { parser, parserOptions, templateString, _, _, paths in
                templateStrings.mutate { $0.append(templateString) }
                let optionsString = parserOptions.map { "\($0.key): \($0.value.value)" }.sorted().joined(separator: ", ")
                parserOptionsStrings.mutate { $0[parser] = optionsString }
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
            let coreDataModelFolder = targetAPath.appending(component: "CoreDataModel.xcdatamodeld")
            let coreDataModelVersionFile = targetAPath.appending(
                components: "CoreDataModel.xcdatamodeld",
                "CoreDataModel.xcdatamodel"
            )

            try await fileSystem.makeDirectory(at:aAssets)
            try await fileSystem.touch(aAsset)
            try await fileSystem.touch(frenchStrings)
            try await fileSystem.touch(frenchStringsDict)
            try await fileSystem.touch(englishStrings)
            try await fileSystem.touch(englishStringsDict)
            try await fileSystem.touch(coreDataModelVersionFile)
            try await fileSystem.writeText("a", at: frenchStrings)
            try await fileSystem.writeText("a", at: frenchStringsDict)
            try await fileSystem.writeText("a", at: englishStrings)
            try await fileSystem.writeText("a", at: englishStringsDict)
            try await fileSystem.touch(emptyPlist)
            try await fileSystem.writeText("a", at: environmentPlist)
            try await fileSystem.writeText("a", at: ttfFont)
            try await fileSystem.writeText("a", at: otfFont)
            try await fileSystem.writeText("a", at: ttcFont)
            let lottieTemplatePath = projectPath.appending(component: "Lottie.stencil")
            try await fileSystem.writeText("lottie template", at: lottieTemplatePath)
            try await fileSystem.writeText("a", at: lottieFile)
            let stringsTemplatePath = projectPath.appending(component: "Strings.stencil")
            try await fileSystem.writeText("strings template", at: stringsTemplatePath)
            let coreDataTemplatePath = projectPath.appending(component: "CoreData.stencil")
            try await fileSystem.writeText("core data template", at: coreDataTemplatePath)
            try await fileSystem.makeDirectory(at:coreDataModelFolder)
            try await fileSystem.writeText("a", at: coreDataModelVersionFile)

            let targetA = Target.test(
                name: "TargetA",
                coreDataModels: [
                    CoreDataModel(
                        path: coreDataModelFolder,
                        versions: [
                            coreDataModelVersionFile,
                        ],
                        currentVersion: "CoreDataModel"
                    ),
                ],
                buildableFolders: [
                    .init(path: "/Sources", exceptions: [], resolvedFiles: [
                        BuildableFolderFile(path: aAssets, compilerFlags: nil),
                        BuildableFolderFile(path: frenchStrings, compilerFlags: nil),
                        BuildableFolderFile(path: frenchStringsDict, compilerFlags: nil),
                        BuildableFolderFile(path: englishStrings, compilerFlags: nil),
                        BuildableFolderFile(path: englishStringsDict, compilerFlags: nil),
                        BuildableFolderFile(path: emptyPlist, compilerFlags: nil),
                        BuildableFolderFile(path: environmentPlist, compilerFlags: nil),
                        BuildableFolderFile(path: ttfFont, compilerFlags: nil),
                        BuildableFolderFile(path: otfFont, compilerFlags: nil),
                        BuildableFolderFile(path: ttcFont, compilerFlags: nil),
                        BuildableFolderFile(path: lottieFile, compilerFlags: nil),
                    ]),
                ]
            )

            let resourceSynthesizers: [ResourceSynthesizer] = [
                .init(
                    parser: .assets,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["xcassets"],
                    template: .defaultTemplate("Assets")
                ),
                .init(
                    parser: .strings,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["strings", "stringsdict"],
                    template: .file(stringsTemplatePath)
                ),
                .init(
                    parser: .plists,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["plist"],
                    template: .defaultTemplate("Plists")
                ),
                .init(
                    parser: .fonts,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["otf", "ttc", "ttf", "woff"],
                    template: .defaultTemplate("Fonts")
                ),
                .init(
                    parser: .json,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["lottie"],
                    template: .file(lottieTemplatePath)
                ),
                .init(
                    parser: .coreData,
                    parserOptions: [
                        "stringValue": "test",
                        "intValue": 999,
                        "boolValue": true,
                        "doubleValue": 1.0,
                    ],
                    extensions: ["xcdatamodeld"],
                    template: .file(coreDataTemplatePath)
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
            let (mappedProject, sideEffects) = try await subject.map(project: project)

            // Then
            let derivedPath = projectPath
                .appending(component: Constants.DerivedDirectory.name)
            let derivedSourcesPath = derivedPath
                .appending(component: Constants.DerivedDirectory.sources)
            let expectedSideEffects: [SideEffectDescriptor] = [
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistAssets+TargetA.swift"),
                        contents: "TargetA/a.xcassets".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistStrings+TargetA.swift"),
                        contents: "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict"
                            .data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistPlists+TargetA.swift"),
                        contents: "TargetA/Environment.plist".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistFonts+TargetA.swift"),
                        contents: "TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistLottie+TargetA.swift"),
                        contents: "TargetA/LottieAnimation.lottie".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "TuistCoreData+TargetA.swift"),
                        contents: "TargetA/CoreDataModel.xcdatamodeld".data(using: .utf8)
                    )
                ),
            ]
            XCTAssertEqual(
                Set(sideEffects.map(\.description)),
                Set(expectedSideEffects.map(\.description))
            )
            let expectedSources: [SourceFile] = [
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistAssets+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/a.xcassets".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistStrings+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash(
                        "en.lproj/aStrings.strings, en.lproj/aStrings.stringsdict".data(using: .utf8)!
                    )
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistPlists+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/Environment.plist".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistFonts+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher
                        .hash("TargetA/otfFont.otf, TargetA/ttcFont.ttc, TargetA/ttfFont.ttf".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistLottie+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/LottieAnimation.lottie".data(using: .utf8)!)
                ),
                SourceFile(
                    path: derivedSourcesPath
                        .appending(component: "TuistCoreData+TargetA.swift"),
                    compilerFlags: nil,
                    contentHash: try contentHasher.hash("TargetA/CoreDataModel.xcdatamodeld".data(using: .utf8)!)
                ),
            ]
            let actualSources = mappedProject.targets[targetA.name]!.sources
                .sorted(by: { $0.path.pathString < $1.path.pathString })
            let sortedExpectedSources = expectedSources.sorted(by: { $0.path.pathString < $1.path.pathString })
            XCTAssertEqual(actualSources, sortedExpectedSources)
            // Check other properties are unchanged
            XCTAssertEqual(mappedProject.path, projectPath)
            XCTAssertEqual(mappedProject.targets.count, 1)
            XCTAssertEqual(mappedProject.targets[targetA.name]?.name, targetA.name)
            XCTAssertEqual(mappedProject.targets[targetA.name]?.coreDataModels, targetA.coreDataModels)
            XCTAssertEqual(
                templateStrings.value.sorted(),
                [
                    SynthesizedResourceInterfaceTemplates.assetsTemplate,
                    "strings template",
                    SynthesizedResourceInterfaceTemplates.plistsTemplate,
                    SynthesizedResourceInterfaceTemplates.fontsTemplate,
                    "lottie template",
                    "core data template",
                ].sorted()
            )
            [
                ResourceSynthesizer.Parser.assets,
                ResourceSynthesizer.Parser.strings,
                ResourceSynthesizer.Parser.plists,
                ResourceSynthesizer.Parser.fonts,
                ResourceSynthesizer.Parser.json,
                ResourceSynthesizer.Parser.coreData,
            ].forEach { parser in
                XCTAssertEqual(
                    parserOptionsStrings.value[parser],
                    "boolValue: true, doubleValue: 1.0, intValue: 999, stringValue: test"
                )
            }
        }
    }

    func testMap_whenDisableSynthesizedResourceAccessors() async throws {
        // Given
        let templateStrings = ThreadSafe<[String]>([])
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, templateString, _, _, paths in
            templateStrings.mutate { $0.append(templateString) }
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
        let coreDataModelFolder = targetAPath.appending(component: "CoreDataModel.xcdatamodeld")
        let coreDataModelVersionFile = targetAPath.appending(
            components: "CoreDataModel.xcdatamodeld",
            "CoreDataModel.xcdatamodel"
        )

        try await fileSystem.makeDirectory(at:aAssets)
        try await fileSystem.touch(aAsset)
        try await fileSystem.touch(frenchStrings)
        try await fileSystem.touch(frenchStringsDict)
        try await fileSystem.touch(englishStrings)
        try await fileSystem.touch(englishStringsDict)
        try await fileSystem.writeText("a", at: frenchStrings)
        try await fileSystem.writeText("a", at: frenchStringsDict)
        try await fileSystem.writeText("a", at: englishStrings)
        try await fileSystem.writeText("a", at: englishStringsDict)
        try await fileSystem.touch(emptyPlist)
        try await fileSystem.writeText("a", at: environmentPlist)
        try await fileSystem.writeText("a", at: ttfFont)
        try await fileSystem.writeText("a", at: otfFont)
        try await fileSystem.writeText("a", at: ttcFont)
        let lottieTemplatePath = projectPath.appending(component: "Lottie.stencil")
        try await fileSystem.writeText("lottie template", at: lottieTemplatePath)
        try await fileSystem.writeText("a", at: lottieFile)
        let stringsTemplatePath = projectPath.appending(component: "Strings.stencil")
        try await fileSystem.writeText("strings template", at: stringsTemplatePath)
        let coreDataTemplatePath = projectPath.appending(component: "CoreData.stencil")
        try await fileSystem.writeText("core data template", at: coreDataTemplatePath)
        try await fileSystem.makeDirectory(at:coreDataModelFolder)
        try await fileSystem.writeText("a", at: coreDataModelVersionFile)

        let targetA = Target.test(
            name: "TargetA",
            resources: .init(
                [
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
        )

        let resourceSynthesizers: [ResourceSynthesizer] = [
            .init(
                parser: .assets,
                parserOptions: [:],
                extensions: ["xcassets"],
                template: .defaultTemplate("Assets")
            ),
            .init(
                parser: .strings,
                parserOptions: [:],
                extensions: ["strings", "stringsdict"],
                template: .file(stringsTemplatePath)
            ),
            .init(
                parser: .plists,
                parserOptions: [:],
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
            .init(
                parser: .fonts,
                parserOptions: [:],
                extensions: ["otf", "ttc", "ttf", "woff"],
                template: .defaultTemplate("Fonts")
            ),
            .init(
                parser: .json,
                parserOptions: [:],
                extensions: ["lottie"],
                template: .file(lottieTemplatePath)
            ),
            .init(
                parser: .coreData,
                parserOptions: [
                    "stringValue": "test",
                    "intValue": 999,
                    "boolValue": true,
                    "doubleValue": 1.0,
                ],
                extensions: ["xcdatamodeld"],
                template: .file(coreDataTemplatePath)
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
        let (mappedProject, sideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEqual(project, mappedProject)
        XCTAssertEqual(sideEffects, [])
    }

    func testMap_bundleName_whenBundleAccessorsAreEnabled() async throws {
        // Given
        let bundleNames = ThreadSafe<[String?]>([])
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, _, bundleName, _ in
            bundleNames.mutate { $0.append(bundleName) }
            return ""
        }
        let projectPath = try temporaryPath()
        let targetPath = projectPath.appending(component: "TargetA")
        let ttfFont = targetPath.appending(component: "ttfFont.ttf")
        try await stub(file: ttfFont)

        let project: Project = .test(
            options: .test(
                disableBundleAccessors: false,
                disableSynthesizedResourceAccessors: false
            ),
            targets: [
                .test(
                    name: "TargetA",
                    resources: .init(
                        [
                            .file(path: ttfFont),
                        ]
                    )
                ),
            ],
            resourceSynthesizers: makeResourceSynthesizers()
        )

        // When
        _ = try await subject.map(project: project)

        // Then
        XCTAssertEqual(bundleNames.value, [
            "Bundle.module",
        ])
    }

    func testMap_bundleName_whenBundleAccessorsAreDisabled() async throws {
        // Given
        let bundleNames = ThreadSafe<[String?]>([])
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, _, bundleName, _ in
            bundleNames.mutate { $0.append(bundleName) }
            return ""
        }
        let projectPath = try temporaryPath()
        let targetPath = projectPath.appending(component: "TargetA")
        let ttfFont = targetPath.appending(component: "ttfFont.ttf")
        try await stub(file: ttfFont)

        let project: Project = .test(
            options: .test(
                disableBundleAccessors: true,
                disableSynthesizedResourceAccessors: false
            ),
            targets: [
                .test(
                    name: "TargetA",
                    resources: .init(
                        [
                            .file(path: ttfFont),
                        ]
                    )
                ),
            ],
            resourceSynthesizers: makeResourceSynthesizers()
        )

        // When
        _ = try await subject.map(project: project)

        // Then
        XCTAssertEqual(bundleNames.value, [
            nil,
        ])
    }

    func testMap_whenResourceContainsBinaryPlist() async throws {
        // Given
        let plistNames = ThreadSafe<[String]>([])
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, _, _, _, paths in
            plistNames.mutate { $0.append(contentsOf: paths.map(\.basename)) }
            return ""
        }
        let projectPath = try temporaryPath()
        let targetPath = projectPath.appending(component: "TargetA")
        let binaryPlist = targetPath.appending(component: "Binary.plist")
        let xmlPlist = targetPath.appending(component: "XML.plist")
        try await fileSystem.makeDirectory(at:targetPath)
        // Create binary plist
        let binaryData = try PropertyListSerialization.data(
            fromPropertyList: ["key": "value"],
            format: .binary,
            options: 0
        )
        try binaryData.write(to: URL(fileURLWithPath: binaryPlist.pathString))
        // Create xml plist
        let xmlData = try PropertyListSerialization.data(
            fromPropertyList: ["key": "value"],
            format: .xml,
            options: 0
        )
        try xmlData.write(to: URL(fileURLWithPath: xmlPlist.pathString))
        let target = Target.test(
            name: "TargetA",
            resources: .init([.file(path: binaryPlist), .file(path: xmlPlist)])
        )
        let resourceSynthesizers: [ResourceSynthesizer] = [
            .init(
                parser: .plists,
                parserOptions: [:],
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
        ]
        let project = Project.test(
            path: projectPath,
            targets: [target],
            resourceSynthesizers: resourceSynthesizers
        )

        // When
        _ = try await subject.map(project: project)

        // Then
        XCTAssertFalse(plistNames.value.contains("Binary.plist"))
        XCTAssertTrue(plistNames.value.contains("XML.plist"))
    }

    // MARK: - Helpers

    private func stub(file: AbsolutePath) async throws {
        try await fileSystem.touch(file)
        try await fileSystem.writeText("a", at: file)
    }

    private func makeResourceSynthesizers() -> [ResourceSynthesizer] {
        [
            .init(
                parser: .assets,
                parserOptions: [:],
                extensions: ["xcassets"],
                template: .defaultTemplate("Assets")
            ),
            .init(
                parser: .plists,
                parserOptions: [:],
                extensions: ["plist"],
                template: .defaultTemplate("Plists")
            ),
            .init(
                parser: .fonts,
                parserOptions: [:],
                extensions: ["otf", "ttc", "ttf", "woff"],
                template: .defaultTemplate("Fonts")
            ),
        ]
    }
}
