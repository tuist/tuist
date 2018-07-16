import Basic
import Foundation
import xpmcore

protocol Installing: AnyObject {
    func install(reference: String, path: AbsolutePath) throws
}

final class Installer: Installing {

    // MARK: - Attributes

    /// Shell.
    let shell: Shelling

    // MARK: - Init

    init(shell: Shelling) {
        self.shell = shell
    }

    // MARK: - Installing

    func install(reference: String, path: AbsolutePath) throws {
        let installationDirectory = path.appending(component: reference)
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        // git clone xxx
        // git checkout reference
        // swift build
        // copy files.
    }
}
