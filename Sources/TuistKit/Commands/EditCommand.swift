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
    private let permanentArgument: OptionArgument<Bool>

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
        permanentArgument = subparser.add(option: "--permanent",
                                          shortName: "-P",
                                          kind: Bool.self,
                                          usage: "It creates the project in the current directory or the one indicated by -p and doesn't block the process.") // swiftlint:disable:this line_length

        self.projectEditor = projectEditor
        self.opener = opener
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let permanent = self.permanent(arguments: arguments)
        let generationDirectory = permanent ? path : EditCommand.temporaryDirectory.path
        let xcodeprojPath = try projectEditor.edit(at: path, in: generationDirectory)

        if !permanent {
            Signals.trap(signals: [.int, .abrt]) { _ in
                // swiftlint:disable:next force_try
                try! FileHandler.shared.delete(EditCommand.temporaryDirectory.path)
                exit(0)
            }
            logger.pretty("Opening Xcode to edit the project. Press \(.keystroke("CTRL + C")) once you are done editing")
            try opener.open(path: xcodeprojPath)
        } else {
            logger.notice("Xcode project generated at \(xcodeprojPath.pathString)", metadata: .success)
        }
    }

    // MARK: - Fileprivate

    fileprivate static var _temporaryDirectory: TemporaryDirectory?
    fileprivate static var temporaryDirectory: TemporaryDirectory {
        // swiftlint:disable:next identifier_name
        if let _temporaryDirectory = _temporaryDirectory { return _temporaryDirectory }
        // swiftlint:disable:next force_try
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

    private func permanent(arguments: ArgumentParser.Result) -> Bool {
        if let permanent = arguments.get(permanentArgument) {
            return permanent
        } else {
            return false
        }
    }
}
