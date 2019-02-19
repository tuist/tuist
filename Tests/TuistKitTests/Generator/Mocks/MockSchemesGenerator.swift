import Foundation
@testable import TuistKit

final class MockSchemesGenerator: SchemesGenerating {
    var generateTargetSchemesArgs: [(project: Project, generatedProject: GeneratedProject)] = []

    func generateSchemes(project: Project, generatedProject: GeneratedProject) throws {
        generateTargetSchemesArgs.append((project: project, generatedProject: generatedProject))
    }
}
