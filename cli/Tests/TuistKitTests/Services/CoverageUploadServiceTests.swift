import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistServer
import TuistTesting
import TuistXCResultService
import XCResultParser
@testable import TuistKit

struct CoverageUploadServiceTests {
    private let xcResultService = MockXCResultServicing()
    private let settingsService = MockGetCoverageSettingsServicing()
    private let createUploadService = MockCreateCoverageUploadServicing()
    private let uploader = MockCoverageFileUploading()
    private let subject: CoverageUploadService
    private let manifest = XcodeCoverageManifest(rootDirectories: ["/repo"], partial: true, files: [])
    private let serverURL = URL(string: "https://tuist.dev")!

    init() {
        subject = CoverageUploadService(
            xcResultService: xcResultService,
            settingsService: settingsService,
            createUploadService: createUploadService,
            uploader: uploader
        )
    }

    private func stubParser(files: Int) {
        given(xcResultService)
            .parseCoverage(path: .any, manifest: .any, into: .any)
            .willProduce { _, manifest, output in
                let lines = (0 ..< files).map { index in
                    """
                    {"path":"Sources/File\(
                        index
                    ).swift","targets":["A"],"is_test":false,"covered_lines":1,"executable_lines":2,"line_numbers":[1,2],"execution_counts":[1,0],"functions":[]}
                    """
                }
                try (lines.joined(separator: "\n") + "\n").write(toFile: output.pathString, atomically: true, encoding: .utf8)
                return XcodeCoverageSummary(partial: manifest.partial, fileCount: files)
            }
    }

    @Test(.withMockedDependencies()) func sendsSmallCoverageInline() async throws {
        stubParser(files: 3)
        given(settingsService).inlineThresholdBytes(fullHandle: .any, serverURL: .any).willReturn(5_000_000)

        let prepared = try #require(await subject.prepare(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: manifest,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        ))

        let inline = try #require(prepared.inline)
        #expect(inline.partial == true)
        #expect(inline.files.map(\.path) == ["Sources/File0.swift", "Sources/File1.swift", "Sources/File2.swift"])
        #expect(prepared.upload == nil)
        #expect(prepared.testRunId == nil)
        verify(uploader).upload(file: .any, to: .any).called(0)
    }

    @Test(.withMockedDependencies()) func uploadsLargeCoverageUnderAFreshRunId() async throws {
        stubParser(files: 3)
        given(settingsService).inlineThresholdBytes(fullHandle: .any, serverURL: .any).willReturn(0)
        given(createUploadService)
            .createCoverageUpload(fullHandle: .value("tuist/tuist"), serverURL: .any, testRunId: .any)
            .willProduce { _, _, testRunId in
                (
                    storageKey: "tuist/tuist/runs/\(testRunId)/coverage.ndjson.deflate",
                    uploadURL: URL(string: "https://storage/put")!
                )
            }
        given(uploader).upload(file: .any, to: .value(URL(string: "https://storage/put")!)).willReturn()

        let prepared = try #require(await subject.prepare(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: manifest,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        ))

        #expect(prepared.inline == nil)
        let testRunId = try #require(prepared.testRunId)
        #expect(prepared.upload == XcodeCoverageUpload(
            storageKey: "tuist/tuist/runs/\(testRunId)/coverage.ndjson.deflate",
            partial: true
        ))
        verify(uploader).upload(file: .any, to: .any).called(1)
    }

    @Test(.withMockedDependencies()) func fallsBackToTheDefaultThresholdAndNeverFailsTheRun() async throws {
        stubParser(files: 1)
        given(settingsService)
            .inlineThresholdBytes(fullHandle: .any, serverURL: .any)
            .willThrow(TestError("offline"))

        let prepared = try #require(await subject.prepare(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: manifest,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        ))

        #expect(prepared.inline?.files.count == 1)
    }

    @Test func deflateRoundTrips() async throws {
        let directory = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(atPath: directory.pathString, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory.pathString) }
        let source = directory.appending(component: "in.ndjson")
        let destination = directory.appending(component: "out.deflate")
        let content = String(repeating: "{\"path\":\"Sources/A.swift\"}\n", count: 10000)
        try content.write(toFile: source.pathString, atomically: true, encoding: .utf8)

        try CoverageUploadService.deflate(source, to: destination)

        let compressed = try Data(contentsOf: URL(fileURLWithPath: destination.pathString))
        #expect(compressed.count < content.utf8.count / 10)
        let inflated = try (compressed as NSData).decompressed(using: .zlib) as Data
        #expect(String(decoding: inflated, as: UTF8.self) == content)
    }
}
