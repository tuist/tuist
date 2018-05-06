import Basic
import Foundation
import Utility

/// Command that outputs the version of the tool.
public class VersionCommand: NSObject, Command {
    
    // MARK: - Command
    
    /// Command name.
    public let command = "version"
    
    /// Command description.
    public let overview = "Outputs the current version of xcbuddy."
    
    /// Context
    let context: CommandsContexting
    
    /// Version fetcher.
    let version: () -> String
    
    /// Initializes the command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required init(parser: ArgumentParser) {
        parser.add(subparser: command, overview: overview)
        context = CommandsContext()
        version = VersionCommand.currentVersion
    }
    
    /// Initializes the command with the context.
    ///
    /// - Parameter context: command context.
    /// - Parameter version: version fetcher.
    init(context: CommandsContexting,
         version: @escaping () -> String) {
        self.context = context
        self.version = version
    }
    
    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with arguments: ArgumentParser.Result) {
        self.context.printer.print(self.version())
    }
    
    /// Returns the current application version.
    ///
    /// - Returns: current application version.
    static func currentVersion() -> String {
        let appBundle = Bundle.main
        let info = appBundle.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String) ?? ""
    }
    
}
