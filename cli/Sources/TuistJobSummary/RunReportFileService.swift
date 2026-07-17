import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging

@Mockable
public protocol RunReportFileServicing {
    /// Writes `report` as JSON to `path`, creating intermediate directories and overwriting any
    /// existing file so that retried CI jobs don't fail on a leftover report.
    ///
    /// Relative paths resolve against the working directory. It never throws: a run report that
    /// failed to write must not fail the command it's reporting on.
    func writeRunReport(_ report: RunReportFile, to path: String) async
}

public struct RunReportFileService: RunReportFileServicing {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func writeRunReport(_ report: RunReportFile, to path: String) async {
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
