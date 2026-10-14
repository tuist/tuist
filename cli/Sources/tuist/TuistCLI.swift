import Foundation
import Path
import SwifterPMCore
import TuistAlert
import TuistConstants
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await SwifterPM.withWarningHandler({ AlertController.current.warning(.alert("\($0)")) }) {
            let statusReporter = ProgramStatusReporter()
            try await ProgramStatusReporter.$current.withValue(statusReporter) {
                try await statusReporter.withCommandStatus {
                    try await Constants.$version.withValue(releaseVersion) {
                        try await initDependencies { sessionPaths in
                            try await TuistCommand.main(
                                logFilePath: sessionPaths.logFilePath,
                                sessionDirectory: sessionPaths.sessionDirectory,
                                networkFilePath: sessionPaths.networkFilePath
                            )
                        }
                    }
                }
            }
        }
    }
}
