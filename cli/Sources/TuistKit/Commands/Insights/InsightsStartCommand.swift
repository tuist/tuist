import ArgumentParser
import Foundation

public struct InsightsStartCommand: AsyncParsableCommand {
    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "insights-start",
        abstract: "Start the machine metrics sampler for build insights",
        shouldDisplay: false
    )

    public func run() async throws {
        try await InsightsStartCommandService().run()
    }
}
