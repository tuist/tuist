import ArgumentParser
import TuistServer

public struct RunnerProfileCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "profile",
            abstract: "Manage runner profiles: their machine shapes, Xcode versions, and the branches that save their cache volumes.",
            subcommands: [
                RunnerProfileListCommand.self,
                RunnerProfileCatalogCommand.self,
                RunnerProfileCreateCommand.self,
                RunnerProfileUpdateCommand.self,
                RunnerProfileDeleteCommand.self,
            ]
        )
    }
}

struct RunnerProfileOptions: ParsableArguments {
    @Option(name: .long, help: "Account handle. Defaults to the account in the project's full handle.")
    var account: String?
    @Option(name: .shortAndLong, help: "Project directory.", completion: .directory)
    var path: String?
    @Flag(help: "Return the response as JSON.")
    var json = false
}

struct RunnerProfileCacheOptions: ParsableArguments {
    @Option(
        name: .customLong("save-cache-from"),
        help: "Additional branch name or * pattern whose jobs save the profile's cache volumes. Repeat for several branches. Replaces the current list."
    )
    var saveCacheFrom: [String] = []

    @Flag(
        name: .customLong("clear-save-cache-from"),
        help: "Remove the additional branches that save the profile's cache volumes."
    )
    var clearSaveCacheFrom = false

    @Flag(
        inversion: .prefixedNo,
        help: "Whether every successful job from the repository saves the profile's cache volumes. Pass --no-save-cache-from-all-branches to save only from the default branch and --save-cache-from branches. Omit to keep the current setting."
    )
    var saveCacheFromAllBranches: Bool?

    @Flag(
        inversion: .prefixedNo,
        help: "Whether jobs on each repository's default branch save the profile's cache volumes. Omit to keep the current setting."
    )
    var saveCacheFromDefaultBranch: Bool?

    var branches: [String]? {
        if clearSaveCacheFrom { return [] }
        return saveCacheFrom.isEmpty ? nil : saveCacheFrom
    }

    func validate() throws {
        if clearSaveCacheFrom, !saveCacheFrom.isEmpty {
            throw ValidationError("Pass either --save-cache-from or --clear-save-cache-from, not both.")
        }
    }
}

extension RunnerProfilePlatform: @retroactive ExpressibleByArgument {}
