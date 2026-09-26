import Compression
import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistLogging
import TuistServer
import TuistXCResultService
import XCResultParser

/// A run's coverage, ready to send: inline with the run when small, or already in object
/// storage (under a run id the client chose) when large.
public struct PreparedCoverage: Equatable {
    public let inline: XcodeCoverageReport?
    public let upload: XcodeCoverageUpload?
    /// The run id the upload was made for; the run must be created with it.
    public let testRunId: String?

    public init(inline: XcodeCoverageReport?, upload: XcodeCoverageUpload?, testRunId: String?) {
        self.inline = inline
        self.upload = upload
        self.testRunId = testRunId
    }
}

/// Reads a bundle's coverage through the streaming parser and decides how it travels to the
/// server: DEFLATE-compressed, anything up to the server's inline threshold goes in the run's
/// request; anything larger is PUT to a signed URL first and the run references it. Both keep
/// memory flat in the coverage's size. Failures cost the run its coverage, never the run.
@Mockable
public protocol CoverageUploadServicing {
    func prepare(
        resultBundlePath: AbsolutePath,
        manifest: XcodeCoverageManifest,
        fullHandle: String,
        serverURL: URL
    ) async -> PreparedCoverage?
}

public struct CoverageUploadService: CoverageUploadServicing {
    private let fileSystem: FileSysteming
    private let xcResultService: XCResultServicing
    private let settingsService: GetCoverageSettingsServicing
    private let createUploadService: CreateCoverageUploadServicing
    private let uploader: CoverageFileUploading

    public init(
        fileSystem: FileSysteming = FileSystem(),
        xcResultService: XCResultServicing = XCResultService(),
        settingsService: GetCoverageSettingsServicing = GetCoverageSettingsService(),
        createUploadService: CreateCoverageUploadServicing = CreateCoverageUploadService(),
        uploader: CoverageFileUploading = CoverageFileUploader()
    ) {
        self.fileSystem = fileSystem
        self.xcResultService = xcResultService
        self.settingsService = settingsService
        self.createUploadService = createUploadService
        self.uploader = uploader
    }

    static let defaultInlineThresholdBytes = 5_000_000

    public func prepare(
        resultBundlePath: AbsolutePath,
        manifest: XcodeCoverageManifest,
        fullHandle: String,
        serverURL: URL
    ) async -> PreparedCoverage? {
        do {
            return try await fileSystem.runInTemporaryDirectory(prefix: "tuist-coverage") { directory -> PreparedCoverage? in
                let ndjson = directory.appending(component: "coverage.ndjson")
                guard let summary = try await xcResultService.parseCoverage(
                    path: resultBundlePath,
                    manifest: manifest,
                    into: ndjson
                ) else { return nil }

                let deflated = directory.appending(component: "coverage.ndjson.deflate")
                try Self.deflate(ndjson, to: deflated)
                let size = try FileManager.default.attributesOfItem(atPath: deflated.pathString)[.size] as? Int ?? 0

                let threshold: Int
                do {
                    threshold = try await settingsService.inlineThresholdBytes(fullHandle: fullHandle, serverURL: serverURL)
                } catch {
                    Logger.current.debug("Using the default coverage inline threshold: \(error.localizedDescription)")
                    threshold = Self.defaultInlineThresholdBytes
                }

                if size <= threshold {
                    let files = try XcodeCoverageParser.readFiles(at: ndjson).sorted { $0.path < $1.path }
                    return PreparedCoverage(
                        inline: XcodeCoverageReport(partial: summary.partial, files: files),
                        upload: nil,
                        testRunId: nil
                    )
                }

                let testRunId = UUID().uuidString.lowercased()
                let upload = try await createUploadService.createCoverageUpload(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    testRunId: testRunId
                )
                try await uploader.upload(file: deflated, to: upload.uploadURL)
                Logger.current.debug("Uploaded \(size) bytes of coverage for \(summary.fileCount) files as \(upload.storageKey)")
                return PreparedCoverage(
                    inline: nil,
                    upload: XcodeCoverageUpload(storageKey: upload.storageKey, partial: summary.partial),
                    testRunId: testRunId
                )
            }
        } catch {
            AlertController.current.warning(
                .alert("Failed to send the code coverage of \(resultBundlePath.pathString): \(error.localizedDescription)")
            )
            return nil
        }
    }

    /// Raw DEFLATE, the encoding the server inflates for inline bodies and uploads alike,
    /// streamed through the Compression framework so the file never sits in memory whole.
    static func deflate(_ source: AbsolutePath, to destination: AbsolutePath) throws {
        let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: source.pathString))
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.pathString, contents: nil) else {
            throw CoverageUploadError.cannotWrite(destination)
        }
        let output = try FileHandle(forWritingTo: URL(fileURLWithPath: destination.pathString))
        defer { try? output.close() }

        let filter = try OutputFilter(.compress, using: .zlib) { data in
            if let data { try output.write(contentsOf: data) }
        }
        while true {
            let chunk = try autoreleasepool { try input.read(upToCount: 1 << 20).map { Data($0) } }
            guard let chunk, !chunk.isEmpty else { break }
            try filter.write(chunk)
        }
        try filter.finalize()
    }
}

enum CoverageUploadError: LocalizedError {
    case cannotWrite(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .cannotWrite(path): "Could not write the compressed coverage to \(path.pathString)"
        }
    }
}
