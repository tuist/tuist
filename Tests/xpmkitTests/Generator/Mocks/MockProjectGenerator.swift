import Basic
import Foundation
@testable import xpmkit

final class MockProjectGenerator: ProjectGenerating {
    func generate(project _: Project, sourceRootPath _: AbsolutePath?, context _: GeneratorContexting, options _: GenerationOptions) throws -> AbsolutePath {
        return AbsolutePath("/")
    }
}
