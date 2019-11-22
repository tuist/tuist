import Basic
import Foundation
import Signals
import SPMUtility
import TuistGenerator
import TuistSupport

class EditCommand: NSObject, Command {
    // MARK: - Static

    static let command = "edit"
    static let overview = "Generates a temporary project to edit the project in the current directory"

    // MARK: - Attributes

    private let projectEditor: ProjectEditing
    private let opener: Opening
    private let pathArgument: OptionArgument<String>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, projectEditor: ProjectEditor(), opener: Opener())
    }

    init(parser: ArgumentParser, projectEditor: ProjectEditing, opener: Opening) {
        let subparser = parser.add(subparser: EditCommand.command, overview: EditCommand.overview)
        pathArgument = subparser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory whose project will be edited.",
                                     completion: .filename)
        self.projectEditor = projectEditor
        self.opener = opener
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)

        let xcodeprojPath = try projectEditor.edit(at: path, in: EditCommand.temporaryDirectory.path)
        Printer.shared.print("Opening Xcode to edit the project. Press CTRL + C once you are done editing")
        try opener.open(path: xcodeprojPath)

        Signals.trap(signals: [.int, .abrt]) { _ in
            try! FileHandler.shared.delete(EditCommand.temporaryDirectory.path)
            exit(0)
        }
        let semaphore = DispatchSemaphore(value: 0)
        semaphore.wait()
    }

    // MARK: - Fileprivate

    fileprivate static var _temporaryDirectory: TemporaryDirectory?
    fileprivate static var temporaryDirectory: TemporaryDirectory {
        if let _temporaryDirectory = _temporaryDirectory { return _temporaryDirectory }
        _temporaryDirectory = try! TemporaryDirectory(removeTreeOnDeinit: true)
        return _temporaryDirectory!
    }

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
