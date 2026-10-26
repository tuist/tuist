import Foundation
import Path
import SwifterPMCore
import TuistAlert
import TuistCargoCommand
import TuistConstants
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        if let arguments = CargoCommand.delegatedArguments(in: CommandLine.arguments), arguments.first == "__compiler" {
            do {
                let command = try CargoCommand.parse(arguments)
                try await command.run()
            } catch { CargoCommand.exit(withError: error) }
            return
        }
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
