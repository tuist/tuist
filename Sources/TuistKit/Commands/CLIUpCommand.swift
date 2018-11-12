import Basic
import Foundation
import TuistCore
import Utility

class CLIUpCommand: NSObject, Command {
    // MARK: - Attributes
    
    static let command = "up"
    static let overview = "Configures the environment for the project."
    fileprivate let fileHandler: FileHandling
    fileprivate let printer: Printing
    fileprivate let graphLoader: GraphLoading

    // MARK: - Init
    
    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  graphLoader: GraphLoader())
    }
    
    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         graphLoader: GraphLoading) {
        parser.add(subparser: CLIUpCommand.command, overview: CLIUpCommand.overview)
        self.fileHandler = fileHandler
        self.printer = printer
        self.graphLoader = graphLoader
    }
    
    func run(with arguments: ArgumentParser.Result) throws {
        let graph = try graphLoader.load(path: fileHandler.currentPath)
        let projects = graph.projects
    }
 
}
