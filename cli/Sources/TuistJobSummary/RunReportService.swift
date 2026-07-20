import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging

@Mockable
public protocol RunReportServicing {
    /// Removes any file at `path`, so that a run which never gets as far as writing its report
    /// leaves nothing behind rather than a report from an earlier run.
    ///
    /// Relative paths resolve against the working directory. It never throws.
    func clearRunReport(at path: String) async

    /// Writes `report` as JSON to `path`, creating intermediate directories and overwriting any
    /// existing file so that retried CI jobs don't fail on a leftover report.
    ///
    /// Relative paths resolve against the working directory. It never throws: a run report that
    /// failed to write must not fail the command it's reporting on.
    func writeRunReport(_ report: RunReport, to path: String) async
}

public struct RunReportService: RunReportServicing {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func clearRunReport(at path: String) async {
        do {
            let outputPath = try await Environment.current.pathRelativeToWorkingDirectory(path)
            guard try await fileSystem.exists(outputPath) else { return }
            try await fileSystem.remove(outputPath)
            Logger.current.debug("Cleared the stale Tuist Run Report at \(outputPath.pathString).")
        } catch {
            Logger.current.warning("Failed to clear the run report at \(path): \(String(describing: error))")
        }
    }

    public func writeRunReport(_ report: RunReport, to path: String) async {
        do {
            let outputPath = try await Environment.current.pathRelativeToWorkingDirectory(path)

            if !(try await fileSystem.exists(outputPath.parentDirectory)) {
                try await fileSystem.makeDirectory(at: outputPath.parentDirectory)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try await fileSystem.writeAsJSON(report, at: outputPath, encoder: encoder, options: [.overwrite])

            Logger.current.debug("Wrote the Tuist Run Report to \(outputPath.pathString).")
        } catch {
            Logger.current.warning("Failed to write the run report to \(path): \(String(describing: error))")
        }
    }
}
