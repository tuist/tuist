import ArgumentParser
import Foundation
import TuistNooraExtension
import TuistServer

public struct RunnerProfileUpdateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Change a profile's machine shape, Xcode version, or the branches that save its cache volumes. Omitted options keep their value."
    )

    @Argument(help: "Profile name, without the runs-on label prefix.")
    var name: String

    @Option(name: .long, help: "vCPUs of an available shape for the profile's platform. Pass with --memory-gb.")
    var vcpus: Int?

    @Option(name: .customLong("memory-gb"), help: "Memory in GB of an available shape for the profile's platform.")
    var memoryGB: Int?

    @Option(name: .customLong("xcode-version"), help: "An available Xcode version for a macOS profile.")
    var xcodeVersion: String?

    @OptionGroup var cacheOptions: RunnerProfileCacheOptions

    @OptionGroup var options: RunnerProfileOptions

    var changes: RunnerProfileChanges {
        RunnerProfileChanges(
            vcpus: vcpus,
            memoryGB: memoryGB,
            xcodeVersion: xcodeVersion,
            saveCacheFromAllBranches: cacheOptions.saveCacheFromAllBranches,
            saveCacheFromDefaultBranch: cacheOptions.saveCacheFromDefaultBranch,
            saveCacheFromBranches: cacheOptions.branches
        )
    }

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        if changes == RunnerProfileChanges() {
            throw ValidationError("Pass at least one option to change.")
        }
    }

    public func run() async throws {
        try await RunnerProfileUpdateCommandService().run(
            name: name,
            changes: changes,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
