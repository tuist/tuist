import Darwin
import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

/// Measures the coverage parser on real `xccov` output, on demand:
///
///     TUIST_COVERAGE_BENCHMARK_REPORT=report.json TUIST_COVERAGE_BENCHMARK_ARCHIVE=archive.json \
///       swift test --filter XcodeCoverageParserBenchmarks
///
/// The two files are what `xcrun xccov view --report --json` and `--archive --json` print for
/// a bundle. `TUIST_COVERAGE_BENCHMARK_MODE` picks `streaming` (the parser as shipped) or
/// `decode-all` (the previous approach: both documents decoded whole). Peak memory is the
/// process's lifetime maximum physical footprint, so run one mode per process.
struct XcodeCoverageParserBenchmarks {
    /// Hands the parser the fixture files as xccov's output, copied rather than read, so the
    /// benchmark measures the parser and not the stub.
    private struct FileStub {
        let report: URL
        let archive: URL

        func source(_ arguments: [String]) -> URL {
            arguments.contains("--archive") ? archive : report
        }

        func execute(_ arguments: [String], to url: URL) throws -> XCResultToolOutput {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: source(arguments), to: url)
            return XCResultToolOutput(standardOutput: "", standardError: "", succeeded: true)
        }
    }

    private struct ArchiveLine: Decodable {
        let line: Int
        let isExecutable: Bool
        let executionCount: Int?
    }

    private struct Report: Decodable {
        struct Target: Decodable {
            struct File: Decodable {
                let path: String
                let coveredLines: Int
                let executableLines: Int
            }

            let name: String
            let files: [File]
        }

        let targets: [Target]
    }

    private static func peakFootprintBytes() -> UInt64 {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        return result == 0 ? usage.ri_lifetime_max_phys_footprint : 0
    }

    @Test func benchmark() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let report = environment["TUIST_COVERAGE_BENCHMARK_REPORT"],
              let archive = environment["TUIST_COVERAGE_BENCHMARK_ARCHIVE"]
        else { return }
        let mode = environment["TUIST_COVERAGE_BENCHMARK_MODE"] ?? "streaming"
        let stub = FileStub(report: URL(fileURLWithPath: report), archive: URL(fileURLWithPath: archive))
        let manifest = XcodeCoverageManifest(rootDirectories: ["/"], partial: false, files: [])
        let started = Date()
        var files = 0

        switch mode {
        case "decode-all":
            let data = try Data(contentsOf: stub.archive)
            let decoded = try JSONDecoder().decode([String: [ArchiveLine]].self, from: data)
            let reportData = try Data(contentsOf: stub.report)
            let decodedReport = try JSONDecoder().decode(Report.self, from: reportData)
            files = decoded.count + decodedReport.targets.count
        default:
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID().uuidString).ndjson")
            defer { try? FileManager.default.removeItem(at: output) }
            let summary = try await XcodeCoverageParser(
                execute: { _ in XCResultToolOutput(standardOutput: "", standardError: "", succeeded: true) },
                executeToFile: { arguments, url in try stub.execute(arguments, to: url) }
            ).parse(
                resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
                manifest: manifest,
                into: try AbsolutePath(validating: output.path)
            )
            files = summary?.fileCount ?? 0
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
            print("benchmark ndjson_bytes=\(size)")
        }

        let elapsed = Date().timeIntervalSince(started)
        print(
            "benchmark mode=\(mode) files=\(files) seconds=\(String(format: "%.2f", elapsed)) peak_mb=\(Self.peakFootprintBytes() / 1_048_576)"
        )
    }
}
