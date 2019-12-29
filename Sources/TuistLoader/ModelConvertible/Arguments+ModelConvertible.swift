import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Arguments: ModelConvertible {
    init(manifest: ProjectDescription.Arguments, generatorPaths _: GeneratorPaths) throws {
        self.init(environment: manifest.environment,
                  launch: manifest.launch)
    }
}
