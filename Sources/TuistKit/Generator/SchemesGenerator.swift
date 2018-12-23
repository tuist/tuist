import Basic
import Foundation

protocol SchemesGenerating {}

final class SchemesGenerator {
    func generate(projectPath _: AbsolutePath,
                  project _: Project) throws {}
}
