// import Foundation
// import PathKit
// import SwiftCLI
//
///// Checks if there are updates and updates the app.
// public class DumpCommand: NSObject, Command {
//    /// Name of the command.
//    public let name: String = "dump"
//
//    /// Path of the file.
//    public let path = Parameter()
//
//    /// Description of the command for the cli.
//    public let shortDescription = "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON"
//
//    /// Manifest loader.
//    private let manifestLoader: GraphManifestLoading
//
//    /// File handler.
//    private let fileHandler: FileHandling
//
//    /// Printer.
//    private let printer: Printing
//
//    public convenience override init() {
//        self.init(manifestLoader: GraphManifestLoader(),
//                  fileHandler: FileHandler(),
//                  printer: Printer())
//    }
//
//    init(manifestLoader: GraphManifestLoading,
//         fileHandler: FileHandling,
//         printer: Printing) {
//        self.manifestLoader = manifestLoader
//        self.fileHandler = fileHandler
//        self.printer = printer
//    }
//
//    /// Executes the command
//    ///
//    /// - Throws: an error if something goes wrong.
//    public func execute() throws {
//        do {
//            var _path = Path(path.value)
//            if fileHandler.isRelative(_path) { _path = fileHandler.currentPath + _path }
//            if !fileHandler.exists(_path) {
//                throw "Path \(_path.string) doesn't exist"
//            }
//            let json = try manifestLoader.load(path: _path)
//            printer.print(String(data: json, encoding: .utf8) ?? "")
//        } catch {
//            print(error)
//        }
//    }
// }
