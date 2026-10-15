import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XCResultParser
@testable import TuistKit

struct CoverageExportServiceTests {
    private let lcov = """
    SF:/repo/Sources/Lib/Calculator.swift
    FN:3,$s3Lib10CalculatorV3add_ySi_SitF
    FN:8,$s3Lib10CalculatorV3add_ySi_SitFyycfU_
    FN:14,$s3Lib10CalculatorV8subtract_ySi_SitF
    FNDA:2,$s3Lib10CalculatorV3add_ySi_SitF
    FNDA:1,$s3Lib10CalculatorV3add_ySi_SitFyycfU_
    FNDA:0,$s3Lib10CalculatorV8subtract_ySi_SitF
    FNF:3
    FNH:2
    DA:3,2
    DA:4,2
    DA:8,1
    DA:9,0
    DA:12,2
    DA:14,0
    DA:15,0
    DA:16,140737488355328
    LF:8
    LH:4
    end_of_record
    SF:/repo/Tests/LibTests/CalculatorTests.swift
    FN:5,$s8LibTests0A5TestsC7testAddyyF
    FNDA:1,$s8LibTests0A5TestsC7testAddyyF
    DA:5,1
    DA:6,1
    end_of_record

    """

    private func write(_ content: String, named name: String = "report.lcov") throws -> AbsolutePath {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: name)
        try content.write(toFile: path.pathString, atomically: true, encoding: .utf8)
        return path
    }

    @Test(.inTemporaryDirectory) func readsAReportOneFileAtATime() throws {
        var records: [CoverageExport.LCOVRecord] = []
        try CoverageExport.forEachRecord(in: try write(lcov)) { records.append($0) }

        #expect(records.map(\.path) == ["/repo/Sources/Lib/Calculator.swift", "/repo/Tests/LibTests/CalculatorTests.swift"])
        #expect(records[0].lines.map(\.line) == [3, 4, 8, 9, 12, 14, 15, 16])
        #expect(records[0].functions.map(\.line) == [3, 8, 14])
        #expect(records[0].counts["$s3Lib10CalculatorV3add_ySi_SitF"] == 2)
        #expect(records[1].lines.map(\.count) == [1, 1])
        #expect(try CoverageExport.functionNames(in: try write(lcov)).count == 4)
    }

    @Test func countsFunctionsLinesWithinTheirSpanOrUntilTheNextFunction() {
        var record = CoverageExport.LCOVRecord(path: "/repo/Sources/Lib/Calculator.swift")
        record.lines = [(3, 2), (4, 2), (8, 1), (9, 0), (12, 2), (14, 0), (15, 0), (16, 1 << 47)]
        record.functions = [(3, "add"), (8, "closure"), (14, "subtract")]
        record.counts = ["add": 2, "closure": 1, "subtract": 1 << 50]
        let attribution = CoverageExport.Attribution(targets: [
            XcodeCoverageTarget(name: "Lib.framework", buildProductPath: "/p/Lib.framework/Lib", files: [record.path]),
            XcodeCoverageTarget(name: "LibTests.xctest", buildProductPath: "/p/LibTests.xctest/LibTests", files: [record.path]),
        ])
        // The mapping knows `add` spans lines 3 to 12, its closure included; `subtract` has no span.
        let mapping = CoverageMapping(
            files: [record.path],
            functions: [CoverageMapping.Function(
                reference: CoverageObserverOutput.nameReference("add"),
                hash: 1,
                expressions: [],
                regions: [
                    (
                        file: 0,
                        region: .init(
                            kind: .code,
                            counter: .reference(0),
                            lineStart: 3,
                            columnStart: 1,
                            lineEnd: 12,
                            columnEnd: 2
                        )
                    ),
                    (
                        file: 0,
                        region: .init(
                            kind: .gap,
                            counter: .reference(0),
                            lineStart: 13,
                            columnStart: 1,
                            lineEnd: 20,
                            columnEnd: 2
                        )
                    ),
                ]
            )]
        )
        var spans = FunctionSpans()
        spans.add(mapping)

        let file = CoverageExport.file(record, attribution: attribution, spans: spans, demangled: ["add": "Calculator.add(_:_:)"])

        #expect(file.targets == ["Lib.framework"])
        #expect(file.isTest == false)
        #expect(file.lineNumbers == [3, 4, 8, 9, 12, 14, 15, 16])
        // A wrapped count reads as zero.
        #expect(file.executionCounts == [2, 2, 1, 0, 2, 0, 0, 0])
        #expect(file.coveredLines == 4)
        #expect(file.executableLines == 8)
        #expect(file.functions.map(\.name) == ["Calculator.add(_:_:)", "closure", "subtract"])
        #expect(file.functions.map { ($0.executableLines, $0.coveredLines) }.map { "\($0.0)/\($0.1)" } == ["5/4", "3/2", "3/0"])
        #expect(file.functions.map(\.executionCount) == [2, 1, 0])
    }

    @Test func keepsOnlyCountsForTestCode() {
        var record = CoverageExport.LCOVRecord(path: "/repo/Tests/A.swift")
        record.lines = [(5, 1), (6, 0)]
        record.functions = [(5, "testAdd")]
        let attribution = CoverageExport.Attribution(targets: [
            XcodeCoverageTarget(name: "LibTests.xctest", buildProductPath: "/p/LibTests.xctest/LibTests", files: [record.path]),
        ])

        let file = CoverageExport.file(record, attribution: attribution, spans: FunctionSpans(), demangled: [:])

        #expect(file.isTest == true)
        #expect(file.targets == ["LibTests.xctest"])
        #expect((file.coveredLines, file.executableLines) == (1, 2))
        #expect(file.lineNumbers.isEmpty && file.executionCounts.isEmpty && file.functions.isEmpty)

        let unknown = CoverageExport.file(record, attribution: attribution, spans: FunctionSpans(), demangled: [:])
        #expect(unknown.isTest)
        let unlisted = CoverageExport.file(
            CoverageExport.LCOVRecord(path: "/elsewhere/B.swift"), attribution: attribution, spans: FunctionSpans(),
            demangled: [:]
        )
        #expect(unlisted.targets.isEmpty && !unlisted.isTest)
    }

    @Test(.inTemporaryDirectory) func writesTheReportsFirstListingOfEachFile() async throws {
        let first = try write(lcov, named: "0.lcov")
        let second = try write(
            "SF:/repo/Sources/Lib/Calculator.swift\nDA:3,2\nend_of_record\nSF:/repo/Sources/Lib/Other.swift\nDA:1,0\nend_of_record\n",
            named: "1.lcov"
        )
        let output = try #require(FileSystem.temporaryTestDirectory).appending(component: CoverageExport.fileName)
        var demangled: [[String]] = []

        try await CoverageExport.write(
            reports: [first, second],
            attribution: CoverageExport.Attribution(targets: []),
            spans: FunctionSpans(),
            demangle: { names in
                demangled.append(names)
                return Dictionary(uniqueKeysWithValues: names.map { ($0, "demangled \($0)") })
            },
            to: output
        )

        let files = try XcodeCoverageParser.readFiles(at: output)
        #expect(files.map(\.path) == [
            "/repo/Sources/Lib/Calculator.swift", "/repo/Tests/LibTests/CalculatorTests.swift", "/repo/Sources/Lib/Other.swift",
        ])
        #expect(files[0].executableLines == 8)
        #expect(files[0].functions.map(\.name).first == "demangled $s3Lib10CalculatorV3add_ySi_SitF")
        #expect(demangled == [[
            "$s3Lib10CalculatorV3add_ySi_SitF", "$s3Lib10CalculatorV3add_ySi_SitFyycfU_",
            "$s3Lib10CalculatorV8subtract_ySi_SitF", "$s8LibTests0A5TestsC7testAddyyF",
        ], []])
        #expect(try CoverageExport.paths(of: output) == files.map(\.path))
    }

    @Test(.inTemporaryDirectory) func tiesTheExportToTheRepository() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let export = directory.appending(component: CoverageExport.fileName)
        let lines = [
            XcodeCoverageFile(
                path: "/private/tmp/repo/Sources/A.swift", gitBlobId: nil, targets: ["A.framework"],
                coveredLines: 1, executableLines: 2, lineNumbers: [1, 2], executionCounts: [1, 0], functions: []
            ),
            XcodeCoverageFile(
                path: "/tmp/repo/.build/checkouts/Dep/D.swift", gitBlobId: nil, targets: ["Dep.framework"],
                coveredLines: 1, executableLines: 1, lineNumbers: [1], executionCounts: [1], functions: []
            ),
            XcodeCoverageFile(
                path: "/tmp/repo/Sources/Ignored.swift", gitBlobId: nil, targets: ["A.framework"],
                coveredLines: 1, executableLines: 1, lineNumbers: [1], executionCounts: [1], functions: []
            ),
            XcodeCoverageFile(
                path: "/elsewhere/E.swift", gitBlobId: nil, targets: [],
                coveredLines: 1, executableLines: 1, lineNumbers: [1], executionCounts: [1], functions: []
            ),
        ]
        let encoder = JSONEncoder()
        try lines.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
            .write(toFile: export.pathString, atomically: true, encoding: .utf8)
        let output = directory.appending(component: "coverage.ndjson")

        let summary = try CoverageExport.tie(
            export: export,
            manifest: XcodeCoverageManifest(
                rootDirectories: ["/tmp/repo", "/private/tmp/repo"],
                partial: true,
                files: [XcodeCoverageSourceFile(path: "Sources/A.swift", gitBlobId: "aaa")]
            ),
            into: output
        )

        #expect(summary == XcodeCoverageSummary(partial: true, fileCount: 1))
        let files = try XcodeCoverageParser.readFiles(at: output)
        #expect(files.map(\.path) == ["Sources/A.swift"])
        #expect(files[0].gitBlobId == "aaa")
        #expect(files[0].targets == ["A.framework"])
        #expect(files[0].executionCounts == [1, 0])
    }

    @Test(.inTemporaryDirectory) func exportsTheImagesAndArchivesAmongTheProductsOnce() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let image = directory.appending(component: "App")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0]).write(to: URL(fileURLWithPath: image.pathString))
        let archive = directory.appending(component: "Lib")
        try Data("!<arch>\n".utf8).write(to: URL(fileURLWithPath: archive.pathString))
        let text = directory.appending(component: "Notes")
        try Data("not a product".utf8).write(to: URL(fileURLWithPath: text.pathString))
        let link = directory.appending(component: "Current")
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: "App")

        let products = CoverageExportService.products(of: [
            XcodeCoverageTarget(name: "App.app", buildProductPath: image.pathString, files: []),
            XcodeCoverageTarget(name: "Lib.framework", buildProductPath: archive.pathString, files: []),
            XcodeCoverageTarget(name: "Again", buildProductPath: link.pathString, files: []),
            XcodeCoverageTarget(name: "Notes", buildProductPath: text.pathString, files: []),
            XcodeCoverageTarget(
                name: "Missing",
                buildProductPath: directory.appending(component: "Missing").pathString,
                files: []
            ),
            XcodeCoverageTarget(name: "None", buildProductPath: nil, files: []),
        ])

        #expect(products == [
            CoverageExportService.Product(path: image.pathString, kind: .image),
            CoverageExportService.Product(path: archive.pathString, kind: .archive),
        ])
        #expect(CoverageExportService.isSwiftMangled("$s3Lib1fyyF"))
        #expect(!CoverageExportService.isSwiftMangled("-[Foo bar]"))
    }

    @Test(.inTemporaryDirectory) func resolvesTheBuildsTargetsAgainstTheProductsTheRunUsed() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let products = directory.appending(components: "Build", "Products", "Debug-iphonesimulator")
        let stale = directory.appending(components: "Build", "Products", "Debug")
        let cache = directory.appending(component: "Lib.xcframework")
        for (bundle, executable) in [
            (products.appending(component: "App.app"), "App"),
            (products.appending(component: "AppTests.xctest"), "AppTests"),
            (stale.appending(component: "App.app"), "App"),
            (cache.appending(components: "ios-arm64-simulator", "Lib.framework"), "Lib"),
            (cache.appending(components: "ios-arm64", "Lib.framework"), "Lib"),
        ] {
            try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)
            try Data("<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>\(executable)</string></dict></plist>"
                .utf8)
                .write(to: URL(fileURLWithPath: bundle.appending(component: "Info.plist").pathString))
            try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: URL(fileURLWithPath: bundle.appending(component: executable).pathString))
        }
        let macFramework = products.appending(component: "Mac.framework")
        try FileManager.default.createDirectory(
            atPath: macFramework.appending(components: "Versions", "A", "Resources").pathString,
            withIntermediateDirectories: true
        )
        try Data("<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Mac</string></dict></plist>".utf8)
            .write(to: URL(fileURLWithPath: macFramework.appending(components: "Versions", "A", "Resources", "Info.plist")
                    .pathString))
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: URL(fileURLWithPath: macFramework.appending(
            components: "Versions",
            "A",
            "Mac"
        ).pathString))
        try FileManager.default.createSymbolicLink(
            atPath: macFramework.appending(components: "Versions", "Current").pathString,
            withDestinationPath: "A"
        )
        let sources = CoverageBuildSources(
            rootDirectories: ["/tmp/repo", "/private/tmp/repo"],
            files: [:],
            targets: [
                CoverageBuildTarget(name: "App.app", isTest: false, files: ["Sources/App.swift"]),
                CoverageBuildTarget(name: "AppTests.xctest", isTest: true, files: ["Tests/AppTests.swift"]),
                CoverageBuildTarget(name: "Mac.framework", isTest: false, files: ["/elsewhere/Mac.swift"]),
                CoverageBuildTarget(name: "Lib.framework", isTest: false, files: ["Lib/Lib.swift"], binaries: [
                    .init(
                        path: cache.appending(components: "ios-arm64-simulator", "Lib.framework", "Lib").pathString,
                        platform: "ios",
                        simulator: true
                    ),
                    .init(
                        path: cache.appending(components: "ios-arm64", "Lib.framework", "Lib").pathString,
                        platform: "ios",
                        simulator: false
                    ),
                ]),
                CoverageBuildTarget(name: "Gone.framework", isTest: false, files: []),
            ]
        )

        let targets = CoverageExportService.targets(sources, productRoots: [directory.appending(components: "Build", "Products")])

        #expect(targets.map(\.buildProductPath) == [
            products.appending(components: "App.app", "App").pathString,
            products.appending(components: "AppTests.xctest", "AppTests").pathString,
            macFramework.appending(components: "Versions", "Current", "Mac").pathString,
            cache.appending(components: "ios-arm64-simulator", "Lib.framework", "Lib").pathString,
            nil,
        ])
        #expect(targets[0].files == ["/tmp/repo/Sources/App.swift", "/private/tmp/repo/Sources/App.swift"])
        #expect(targets[2].files == ["/elsewhere/Mac.swift"])
        #expect(targets.map(\.isTest) == [false, true, false, false, false])
    }

    @Test func readsThePlatformOffTheProductsDirectoryName() {
        #expect(CoverageExportService.platform(ofProductsDirectory: "Debug") == ("macos", false))
        #expect(CoverageExportService.platform(ofProductsDirectory: "Debug-iphonesimulator") == ("ios", true))
        #expect(CoverageExportService.platform(ofProductsDirectory: "Release-iphoneos") == ("ios", false))
        #expect(CoverageExportService.platform(ofProductsDirectory: "Debug-appletvsimulator") == ("tvos", true))
        #expect(CoverageExportService.platform(ofProductsDirectory: "Debug-watchos") == ("watchos", false))
        #expect(CoverageExportService.platform(ofProductsDirectory: "Debug-xrsimulator") == ("xros", true))
    }

    @Test(.inTemporaryDirectory) func mapsRecordedAliasesBackThroughTheTargetsPrefixMap() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let intermediates = directory.appending(
            components: "Build",
            "Intermediates.noindex",
            "App.build",
            "Debug-iphonesimulator"
        )
        for (target, map) in [
            ("Lib", ["/^src": "/checkout/Lib", "/^built": "/dd/Build/Products"]),
            ("Other", ["/^src": "/checkout/Other"]),
        ] {
            let targetDirectory = intermediates.appending(component: "\(target).build")
            try FileManager.default.createDirectory(atPath: targetDirectory.pathString, withIntermediateDirectories: true)
            try JSONEncoder().encode(map)
                .write(to: URL(fileURLWithPath: targetDirectory.appending(component: "compilation-prefix-map.json").pathString))
        }
        try FileManager.default.createDirectory(
            atPath: directory.appending(components: "existing").pathString,
            withIntermediateDirectories: true
        )

        let maps = CompilationPrefixMaps(derivedDataDirectory: directory)

        #expect(maps.remap("/^src/A.swift", target: "Lib") == "/checkout/Lib/A.swift")
        #expect(maps.remap("/^src/A.swift", target: "Other") == "/checkout/Other/A.swift")
        // A target without a map of its own goes through the first map that knows the alias.
        #expect(maps.remap("/^src/A.swift", target: "LibTests") == "/checkout/Lib/A.swift")
        #expect(maps.remap("/^sdk/usr/include/x.h", target: "Lib") == "/^sdk/usr/include/x.h")
        #expect(maps.remap("/checkout/Lib/A.swift", target: "Lib") == "/checkout/Lib/A.swift")
        #expect(CompilationPrefixMaps(derivedDataDirectory: nil).remap("/^src/A.swift", target: "Lib") == "/^src/A.swift")

        // Among several maps for an alias, the one whose result exists wins.
        let existing = CompilationPrefixMaps(mapsByTarget: [
            "A": ["/^src": "/nowhere"],
            "B": ["/^src": directory.pathString],
        ])
        #expect(existing.remap("/^src/existing", target: "C") == directory.appending(component: "existing").pathString)

        #expect(CompilationPrefixMaps.targetName(ofProduct: "/p/Lib.framework/Versions/A/Lib") == "Lib")
        #expect(CompilationPrefixMaps.targetName(ofProduct: "/p/libLib.a") == "Lib")
        #expect(CompilationPrefixMaps.targetName(ofProduct: "/p/App.app/Contents/MacOS/App") == "App")
        #expect(CompilationPrefixMaps.targetName(ofProduct: "/p/AppTests.xctest/AppTests") == "AppTests")
    }

    @Test(.inTemporaryDirectory) func writesMappedFilesUnderThePathTheyMapBackTo() async throws {
        let report = try write(
            "SF:/^src/Lib/A.swift\nDA:1,1\nend_of_record\nSF:/^src/Lib/A.swift\nDA:1,1\nend_of_record\n",
            named: "0.lcov"
        )
        let output = try #require(FileSystem.temporaryTestDirectory).appending(component: CoverageExport.fileName)
        let attribution = CoverageExport.Attribution(targets: [
            XcodeCoverageTarget(name: "Lib.framework", buildProductPath: nil, files: ["/checkout/Lib/A.swift"]),
        ])

        try await CoverageExport.write(
            reports: [report],
            attribution: attribution,
            spans: FunctionSpans(),
            demangle: { _ in [:] },
            remap: { path, _ in path.replacingOccurrences(of: "/^src", with: "/checkout") },
            to: output
        )

        let files = try XcodeCoverageParser.readFiles(at: output)
        #expect(files.map(\.path) == ["/checkout/Lib/A.swift"])
        #expect(files[0].targets == ["Lib.framework"])
    }

    @Test(.inTemporaryDirectory) func readsTheArchitectureOffAThinImageAndKeepsOnlyThisRunsProfile() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let arm64 = directory.appending(component: "arm64")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]).write(to: URL(fileURLWithPath: arm64.pathString))
        let x86 = directory.appending(component: "x86_64")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01]).write(to: URL(fileURLWithPath: x86.pathString))
        let universal = directory.appending(component: "universal")
        try Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02]).write(to: URL(fileURLWithPath: universal.pathString))
        #expect(CoverageExportService.architecture(ofImage: arm64.pathString) == "arm64")
        #expect(CoverageExportService.architecture(ofImage: x86.pathString) == "x86_64")
        #expect(CoverageExportService.architecture(ofImage: universal.pathString) == nil)

        let old = directory.appending(component: "old.profdata")
        let new = directory.appending(component: "new.profdata")
        try Data().write(to: URL(fileURLWithPath: old.pathString))
        try Data().write(to: URL(fileURLWithPath: new.pathString))
        let runStartedAt = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: runStartedAt.addingTimeInterval(-60)],
            ofItemAtPath: old.pathString
        )
        try FileManager.default.setAttributes(
            [.modificationDate: runStartedAt.addingTimeInterval(60)],
            ofItemAtPath: new.pathString
        )
        #expect(CoverageExportService.newest([old, new], writtenAfter: runStartedAt) == new)
        // An earlier run's profile is not this run's.
        #expect(CoverageExportService.newest([old], writtenAfter: runStartedAt) == nil)
        #expect(CoverageExportService.newest([], writtenAfter: runStartedAt) == nil)
    }

    @Test(.inTemporaryDirectory) func attributesFilesWhateverSpellingTheCompilerRecorded() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let real = directory.appending(component: "checkout")
        try FileManager.default.createDirectory(
            atPath: real.appending(component: "Sources").pathString,
            withIntermediateDirectories: true
        )
        let link = directory.appending(component: "link")
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: "checkout")
        let attribution = CoverageExport.Attribution(targets: [
            XcodeCoverageTarget(
                name: "Lib.framework",
                buildProductPath: nil,
                files: [real.appending(components: "Sources", "A.swift").pathString]
            ),
            XcodeCoverageTarget(
                name: "LibTests.xctest",
                buildProductPath: nil,
                files: [real.appending(components: "Sources", "A.swift").pathString],
                isTest: true
            ),
        ])

        // The compiler saw the checkout through the link; a file the checkout no longer has still matches.
        #expect(attribution.targets(of: link.appending(components: "Sources", "A.swift").pathString).targets == ["Lib.framework"])
        #expect(attribution.targets(of: link.appending(components: "Sources", "Gone", "B.swift").pathString).targets.isEmpty)
        let gone = CoverageExport.Attribution(targets: [
            XcodeCoverageTarget(
                name: "Lib.framework",
                buildProductPath: nil,
                files: [real.appending(components: "Sources", "Gone", "B.swift").pathString]
            ),
        ])
        #expect(gone.targets(of: link.appending(components: "Sources", "Gone", "B.swift").pathString)
            .targets == ["Lib.framework"])
    }
}
