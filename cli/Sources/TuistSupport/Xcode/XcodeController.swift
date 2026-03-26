import Command
import Foundation
import Mockable
import Path
import TSCUtility
import TuistThreadSafe

@Mockable
public protocol XcodeControlling: Sendable {
    func selected() async throws -> Xcode
    func selectedVersion() async throws -> Version
}

public final class XcodeController: XcodeControlling, @unchecked Sendable {
    @TaskLocal public static var current: XcodeControlling = XcodeController()

    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Cached response of `xcode-select` command
    private let selectedXcode: ThreadSafe<Xcode?> = ThreadSafe(nil)

    public func selected() async throws -> Xcode {
        if let selectedXcode = selectedXcode.value {
            return selectedXcode
        } else {
            let path = try await commandRunner.run(arguments: ["xcode-select", "-p"])
                .concatenatedString()
                .spm_chomp()
            let value = try await Xcode.read(path: try AbsolutePath(validating: path).parentDirectory.parentDirectory)
            selectedXcode.mutate { $0 = value }
            return value
        }
    }

    public func selectedVersion() async throws -> Version {
        let xcode = try await selected()
        return try Version(versionString: xcode.infoPlist.version, usesLenientParsing: true)
    }
}
