import Basic
import Foundation
@testable import xcbuddykit

final class MockProjectGenerator: ProjectGenerating {
    func generate(project _: Project, context _: GeneratorContexting) throws -> AbsolutePath {
        return AbsolutePath("/")
    }
}
