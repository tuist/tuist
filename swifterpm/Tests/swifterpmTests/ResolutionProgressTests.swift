import Foundation
import Testing
@testable import SwifterPMCore

struct ResolutionProgressTests {
    @Test
    func reporterPrintsAppendOnlyResolutionProgress() {
        let output = ProgressOutputCollector()
        let reporter = ResolutionProgressReporter(
            minimumInterval: 0,
            writeLine: { output.append($0) }
        )

        reporter.started(rootVersionedDependencies: 1, fixedDependencies: 1)
        reporter.startedFetchingVersions(package: "foo")
        reporter.finishedFetchingVersions(package: "foo", versionCount: 3)
        reporter.selected(package: "foo", version: "1.2.3")
        reporter.startedInspectingManifest(package: "foo", version: "1.2.3")
        reporter.finishedInspectingManifest(package: "foo", version: "1.2.3", dependencyCount: 2)
        reporter.startedResolvingFixedPin(package: "bar")
        reporter.finishedResolvingFixedPin(package: "bar")
        reporter.finished(pinCount: 2)

        let lines = output.lines
        #expect(lines.first == "swifterpm \(swifterpmVersion)")
        #expect(
            lines.contains {
                $0.contains("   2/4 deps · resolving")
            })
        #expect(lines.last?.hasPrefix("✓ resolved 2 packages in ") == true)
    }

    @Test
    func reporterCountsSelectedAndFixedPinsByUniqueIdentity() {
        let output = ProgressOutputCollector()
        let reporter = ResolutionProgressReporter(
            minimumInterval: 0,
            writeLine: { output.append($0) }
        )

        reporter.started(rootVersionedDependencies: 1, fixedDependencies: 1)
        reporter.selected(package: "foo", version: "1.2.3")
        reporter.finishedResolvingFixedPin(package: "foo")

        #expect(
            output.lines.contains {
                $0.contains("   1/2 deps · resolving")
            })
        #expect(
            output.lines.contains {
                $0.contains("   2/2 deps · resolving")
            } == false)
    }

    @Test
    func disabledReporterStaysSilent() {
        let output = ProgressOutputCollector()
        let reporter = ResolutionProgressReporter(
            enabled: false,
            minimumInterval: 0,
            writeLine: { output.append($0) }
        )

        reporter.started(rootVersionedDependencies: 1, fixedDependencies: 0)
        reporter.startedFetchingVersions(package: "foo")
        reporter.finished(pinCount: 1)

        #expect(output.lines.isEmpty)
    }
}

private final class ProgressOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLines: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedLines
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storedLines.append(line)
    }
}
