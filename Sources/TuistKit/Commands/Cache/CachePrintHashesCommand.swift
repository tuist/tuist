import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

public struct CachePrintHashesCommand: AsyncParsableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "print-hashes",
            _superCommandName: "cache",
            abstract: "Print the hashes of the cacheable frameworks in the given project."
        )
    }
    
    // MARK: - Arguments and Flags

    @OptionGroup()
    var options: CacheOptions
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - AsyncParsableCommand

    public func run() async throws {
        try await CachePrintHashesService().run(
            path: options.path,
            xcframeworks: options.xcframeworks,
            destination: options.destination,
            profile: options.profile
        )
    }
}
