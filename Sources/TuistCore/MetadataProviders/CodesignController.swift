import FileSystem
import Path
import Command

public final class CodesignController {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    func codesignSignature(of xcframeworkPath: AbsolutePath) async -> String? {
        do {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/codesign",
                    "-dvv",
                    xcframeworkPath.pathString
                ]
            )
            .concatenatedString()

        } catch {
            /// There's an error thrown when the xcframework is not signed.
            return nil
        }
    }

    func codesignExtractSignature(
        of xcframeworkPath: AbsolutePath,
        workingDirectory: AbsolutePath
    ) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/usr/bin/codesign",
                "-d",
                "--extract-certificates",
                xcframeworkPath.pathString
            ],
            workingDirectory: workingDirectory
        )
        .awaitCompletion()
    }
}
