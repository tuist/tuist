import Foundation
import Testing

@testable import SwifterPMCore

struct RestoreProgressReporterTests {
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [String] = []
        var lines: [String] {
            lock.withLock { _lines }
        }
        func append(_ line: String) {
            lock.withLock { _lines.append(line) }
        }
    }

    @Test
    func reporterOwnsTheRestoreMessageFormatting() {
        let sink = Sink()
        let reporter = RestoreProgressReporter { sink.append($0) }

        reporter.downloadingBinaryArtifact(identity: "ffcomposer-apple", target: "libavdevice")
        reporter.restoredBinaryArtifact(
            identity: "ffcomposer-apple", target: "libavdevice", path: "/cache/libavdevice")
        reporter.restoredPackage(identity: "swift-log", path: "/checkouts/swift-log")
        reporter.restoreSummary(
            sourceCount: 2, sourcePath: "/checkouts",
            registryCount: 1, registryPath: "/registry",
            skipped: 4
        )

        #expect(
            sink.lines == [
                "downloading ffcomposer-apple.libavdevice",
                "restored ffcomposer-apple.libavdevice -> /cache/libavdevice",
                "restored swift-log -> /checkouts/swift-log",
                "restored 2 source-control packages into /checkouts",
                "restored 1 registry packages into /registry",
                "skipped 4 unsupported pins",
            ])
    }

    @Test
    func restoreSummaryOmitsSkippedLineWhenNonePinsSkipped() {
        let sink = Sink()
        let reporter = RestoreProgressReporter { sink.append($0) }

        reporter.restoreSummary(
            sourceCount: 1, sourcePath: "/checkouts",
            registryCount: 0, registryPath: "/registry",
            skipped: 0
        )

        #expect(
            sink.lines == [
                "restored 1 source-control packages into /checkouts",
                "restored 0 registry packages into /registry",
            ])
    }
}
