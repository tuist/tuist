import ArgumentParser
import Foundation

public struct SampleHostMetricsCommand: AsyncParsableCommand {
    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "sample-host-metrics",
        abstract: "Continuously sample host metrics (CPU, memory, network, disk) for build insights",
        shouldDisplay: false
    )

    public func run() async throws {
        try await SampleHostMetricsService().run()
    }
}
