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
    private let nonTemporaryArgument: OptionArgument<Bool>

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

        nonTemporaryArgument = subparser.add(option: "--non-temporary",
                                             shortName: "-n",
                                             kind: Bool.self,
                                             usage: "It creates the project in the current directory or the one indicated by -p and doesn't block the process.")
        self.projectEditor = projectEditor
        self.opener = opener
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let temporary = self.temporary(arguments: arguments)
        let generationDirectory = temporary ? EditCommand.temporaryDirectory.path : path
        let xcodeprojPath = try projectEditor.edit(at: path, in: generationDirectory)

        if !temporary {
            Signals.trap(signals: [.int, .abrt]) { _ in
                try! FileHandler.shared.delete(EditCommand.temporaryDirectory.path)
                exit(0)
            }
        }

        Printer.shared.print("Opening Xcode to edit the project. Press CTRL + C once you are done editing")
        try opener.open(path: xcodeprojPath, wait: temporary)
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

    private func temporary(arguments: ArgumentParser.Result) -> Bool {
        if let nonTemporary = arguments.get(nonTemporaryArgument) {
            return !nonTemporary
        } else {
            return true
        }
    }
}
