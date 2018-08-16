import Basic
import Foundation

class GenerationOptions {
    let buildConfiguration: BuildConfiguration
    let skipCarthage: Bool

    init(buildConfiguration: BuildConfiguration = .debug,
         skipCarthage: Bool = false) {
        self.buildConfiguration = buildConfiguration
        self.skipCarthage = skipCarthage
    }
}
