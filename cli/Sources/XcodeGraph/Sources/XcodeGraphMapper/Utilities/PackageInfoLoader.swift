import Command
import Foundation
import Mockable
import Path
import XcodeGraph

@Mockable
protocol PackageInfoLoading {
    func loadPackageInfo(at path: AbsolutePath) async throws -> PackageInfo
}

struct PackageInfoLoader: PackageInfoLoading {
    private let commandRunner: CommandRunning
    private let decoder = JSONDecoder()

    init(
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.commandRunner = commandRunner
    }

    func loadPackageInfo(at path: AbsolutePath) async throws -> PackageInfo {
        let output = try await commandRunner.run(
            arguments: [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ]
        )
        .concatenatedString()

        let data = Data(output.utf8)

        return try decoder.decode(PackageInfo.self, from: data)
    }
}
