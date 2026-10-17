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

    @Option(
        name: .customLong("save-cache-from"),
        help: "Additional branch name or * pattern whose jobs save the profile's cache volumes. Repeat for several branches."
    )
    var saveCacheFrom: [String] = []

    @Flag(
        inversion: .prefixedNo,
        help: "Whether jobs on each repository's default branch save the profile's cache volumes. Defaults to saving."
    )
    var saveCacheFromDefaultBranch: Bool?

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        switch (platform, xcodeVersion) {
        case (.macos, nil): throw ValidationError("Pass --xcode-version for a macOS profile.")
        case (.linux, .some): throw ValidationError("--xcode-version only applies to macOS profiles.")
        default: break
        }
    }

    public func run() async throws {
        try await RunnerProfileCreateCommandService().run(
            name: name,
            platform: platform,
            vcpus: vcpus,
            memoryGB: memoryGB,
            xcodeVersion: xcodeVersion,
            saveCacheFromDefaultBranch: saveCacheFromDefaultBranch,
            saveCacheFromBranches: saveCacheFrom.isEmpty ? nil : saveCacheFrom,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
