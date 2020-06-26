import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

final class FocusService {

    /// Opener instance to run open in the system.
    private let opener: Opening

    init(opener: Opening = Opener()) {
        self.opener = opener
    }

    func run(cache: Bool) throws {
        let generator = ProjectGenerator(graphMapperProvider: GraphMapperProvider(cache: cache))
        let path = FileHandler.shared.currentPath
        let (workspacePath, _) = try generator.generateProjectWorkspace(path: path)
        try opener.open(path: workspacePath)
    }
}
