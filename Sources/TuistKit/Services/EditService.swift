import Foundation
import Signals
import TSCBasic
import TuistGenerator
import TuistSupport

enum EditServiceError: FatalError {
    case xcodeNotSelected

    var description: String {
        switch self {
        case .xcodeNotSelected:
            return "Couldn't determine the Xcode version to open the project. Make sure your Xcode installation is selected with 'xcode-select -s'."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcodeNotSelected:
            return .abort
        }
    }
}

final class EditService {
    private let projectEditor: ProjectEditing
    private let opener: Opening

    init(projectEditor: ProjectEditing = ProjectEditor(),
         opener: Opening = Opener())
    {
        self.projectEditor = projectEditor
        self.opener = opener
    }

    func run(path: String?,
             permanent: Bool) throws
    {
        let path = self.path(path)

        if !permanent {
            try withTemporaryDirectory { generationDirectory in
                EditService.temporaryDirectory = generationDirectory

                Signals.trap(signals: [.int, .abrt]) { _ in
                    // swiftlint:disable:next force_try
                    try! EditService.temporaryDirectory.map(FileHandler.shared.delete)
                    exit(0)
                }

                guard let selectedXcode = try XcodeController.shared.selected() else {
                    throw EditServiceError.xcodeNotSelected
                }
                let xcodeprojPath = try projectEditor.edit(at: path, in: generationDirectory)
                logger.pretty("Opening Xcode to edit the project. Press \(.keystroke("CTRL + C")) once you are done editing")
                try opener.open(path: xcodeprojPath, application: selectedXcode.path)
            }
        } else {
            let xcodeprojPath = try projectEditor.edit(at: path, in: path)
            logger.notice("Xcode project generated at \(xcodeprojPath.pathString)", metadata: .success)
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private static var temporaryDirectory: AbsolutePath?
}
