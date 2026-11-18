import ArgumentParser
import Foundation
import Path
import TuistEnvironment
import TuistEnvKey
import TuistNooraExtension

public struct SnapshotsCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "snapshots",
            abstract: "Upload snapshot test images to Tuist, which compares them with their baseline for review, and download baselines to verify against locally.",
            subcommands: [SnapshotsUploadCommand.self, SnapshotsDownloadCommand.self]
        )
    }
}

public struct SnapshotsUploadCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "upload",
            abstract: "Upload a directory of recorded snapshot images as a snapshot build of the current commit.",
            discussion: """
            Uploads every PNG in the directory, named by its path relative to it, with the metadata of the JSON file next to it \
            (display_name, group, tags, diff_threshold), the format the tuist/snapshots library writes to SNAPSHOTS_EXPORT_DIR. \
            Tuist compares the images with the baseline of the set, and the command fails when they changed and nobody approved the changes.
            """
        )
    }

    @Argument(help: "The directory the snapshot images were recorded to.", completion: .directory)
    var directory: String

    @Option(
        name: .long,
        help: "The snapshot set, such as 'ios-iphone': builds are compared within a set.",
        envKey: .snapshotsUploadSet
    )
    var set: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory,
        envKey: .snapshotsUploadPath
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration.",
        envKey: .snapshotsUploadFullHandle
    )
    var fullHandle: String?

    @Option(
        help: "The share of pixels, from 0 to 1, that may differ from the baseline before an image counts as changed, for images whose metadata doesn't set one.",
        envKey: .snapshotsUploadDiffThreshold
    )
    var diffThreshold: Double?

    @Flag(
        help: "The run rendered only some of the images: baseline images it didn't upload are skipped, not removed.",
        envKey: .snapshotsUploadSelective
    )
    var selective: Bool = false

    @Option(
        help: "A file listing every image the suite renders, one name per line, for a run that rendered only some. Defaults to tuist-all-image-names.txt in the directory.",
        completion: .file(),
        envKey: .snapshotsUploadAllImageNamesFile
    )
    var allImageNamesFile: String?

    @Flag(
        help: "Fail when the images changed against the baseline and nobody approved the changes yet, or a reviewer rejected them.",
        envKey: .snapshotsUploadFailOnChanges
    )
    var failOnChanges: Bool = true

    @Flag(help: "Print the snapshot build as JSON.", envKey: .snapshotsUploadJSON)
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func validate() throws {
        if let diffThreshold, !(0 ... 1).contains(diffThreshold) {
            throw ValidationError("--diff-threshold must be between 0 and 1.")
        }
    }

    public func run() async throws {
        let environment = Environment.current
        var allImageNamesFilePath: AbsolutePath?
        if let allImageNamesFile {
            allImageNamesFilePath = try await environment.pathRelativeToWorkingDirectory(allImageNamesFile)
        }
        try await SnapshotsUploadService().upload(
            directory: try await environment.pathRelativeToWorkingDirectory(directory),
            options: SnapshotsUploadOptions(
                set: set,
                path: try await environment.pathRelativeToWorkingDirectory(path),
                fullHandle: fullHandle,
                diffThreshold: diffThreshold,
                selective: selective,
                allImageNamesFile: allImageNamesFilePath,
                failOnChanges: failOnChanges,
                json: json
            )
        )
    }
}

public struct SnapshotsDownloadCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "download",
            abstract: "Download the baseline images the current checkout's snapshots are compared with.",
            discussion: """
            Writes the images of the set's baseline for the current commit (the default branch's build at the merge base, \
            as an upload would be compared with) to the directory, named as they were uploaded. Point a snapshot library's \
            reference directory at it to verify images locally instead of keeping them in the repository. Files that already \
            hold the right image aren't downloaded again.
            """
        )
    }

    @Argument(help: "The directory to write the baseline images to.", completion: .directory)
    var directory: String

    @Option(
        name: .long,
        help: "The snapshot set, such as 'ios-iphone'.",
        envKey: .snapshotsDownloadSet
    )
    var set: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory,
        envKey: .snapshotsDownloadPath
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration.",
        envKey: .snapshotsDownloadFullHandle
    )
    var fullHandle: String?

    @Flag(help: "Print the result as JSON.", envKey: .snapshotsDownloadJSON)
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        let environment = Environment.current
        try await SnapshotsDownloadService().download(
            directory: try await environment.pathRelativeToWorkingDirectory(directory),
            options: SnapshotsDownloadOptions(
                set: set,
                path: try await environment.pathRelativeToWorkingDirectory(path),
                fullHandle: fullHandle,
                json: json
            )
        )
    }
}
