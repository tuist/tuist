import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Arguments {
    static func from(manifest: ProjectDescription.Arguments) -> TuistCore.Arguments {
        Arguments(environment: manifest.environment,
                  launch: manifest.launch)
    }
}
