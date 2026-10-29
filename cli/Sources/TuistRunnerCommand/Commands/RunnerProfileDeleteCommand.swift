import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerProfileDeleteCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a runner profile. Jobs that request its runs-on label stop being picked up; running jobs finish."
    )

    @Argument(help: "Profile name, without the runs-on label prefix.")
    var name: String

    @Flag(name: .long, help: "Confirm deleting the profile.")
    var yes = false

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        guard yes else { throw ValidationError("Pass --yes to confirm deleting the profile.") }
    }

    public func run() async throws {
        try await RunnerProfileDeleteCommandService().run(
            name: name,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
