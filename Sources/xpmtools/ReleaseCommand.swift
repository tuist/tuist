import Basic
import Foundation
import Utility
import xpmcore

public class ReleaseCommand: NSObject, Command {
    public static let command = "release"
    public static let overview = "Releases a new version of xpm"
    private let fileManager: FileManager = .default

    public required init(parser: ArgumentParser) {
        _ = parser.add(subparser: ReleaseCommand.command, overview: ReleaseCommand.overview)
    }

    public func run(with _: ArgumentParser.Result) throws {
        try Process.checkNonZeroExit(args: "swift", "build", "--configuration", "release")
    }
}
