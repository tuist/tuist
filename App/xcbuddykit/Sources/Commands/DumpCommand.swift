import Foundation
import Sparkle
import Utility
import Basic

public class DumpCommand: NSObject, Command, SPUUpdaterDelegate {
    
    public let command = "dump"
    public let overview = "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON."
    fileprivate let context: GraphLoaderContexting
    fileprivate let printer: Printing
    
    required public init(parser: ArgumentParser) {
        parser.add(subparser: command, overview: overview)
        self.context = GraphLoaderContext(projectPath: AbsolutePath.current)
        self.printer = Printer()
    }
    
    init(printer: Printing,
         context: GraphLoaderContexting) {
        self.printer = printer
        self.context = context
    }
    
    public func run(with arguments: ArgumentParser.Result) throws {
        do {
            let path = AbsolutePath.current
            if !context.fileHandler.exists(path) {
                throw "Path \(path.asString) doesn't exist"
            }
            let json: JSON = try context.manifestLoader.load(path: path, context: context)
            printer.print(json.toString(prettyPrint: true))
        } catch {
            print(error)
        }
    }
    
}
