import Basic
import Foundation
import RxBlocking
import RxSwift
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

final class FocusService {
    /// Generator instance to generate the project workspace.
    private let generator: ProjectGenerating

    /// Opener instance to run open in the system.
    private let opener: Opening
    
    init(generator: ProjectGenerating = ProjectGenerator(),
         opener: Opening = Opener()) {
        self.generator = generator
        self.opener = opener
    }
    
    func run() throws {
        let path = FileHandler.shared.currentPath

        let workspacePath = try generator.generate(path: path,
                                                   projectOnly: false)

        try opener.open(path: workspacePath)
    }
}
