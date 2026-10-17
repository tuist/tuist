import ArgumentParser
import Foundation
import TuistNooraExtension
import TuistServer

public struct RunnerProfileCreateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a runner profile. Run 'tuist runner profile options' for the available shapes and Xcode versions."
    )

    @Argument(
        help: "Profile name: up to 32 lowercase letters, digits, and hyphens, starting with a letter. Workflows use it as runs-on: tuist-<name>."
    )
    var name: String

    @Option(name: .long, help: "The platform the profile's jobs run on.")
    var platform: RunnerProfilePlatform

    @Option(name: .long, help: "vCPUs of an available shape for the platform.")
    var vcpus: Int

    @Option(name: .customLong("memory-gb"), help: "Memory in GB of an available shape for the platform.")
    var memoryGB: Int

    @Option(name: .customLong("xcode-version"), help: "An available Xcode version. Required for macOS profiles.")
    var xcodeVersion: String?

    @OptionGroup var cacheOptions: RunnerProfileCacheOptions

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        if platform == .macos, xcodeVersion == nil {
            throw ValidationError("Pass --xcode-version for a macOS profile.")
        }
    }

    public func run() async throws {
        try await RunnerProfileCreateCommandService().run(
            name: name,
            platform: platform,
            vcpus: vcpus,
            memoryGB: memoryGB,
            xcodeVersion: xcodeVersion,
            saveCacheFromDefaultBranch: cacheOptions.saveCacheFromDefaultBranch,
            saveCacheFromBranches: cacheOptions.branches,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
