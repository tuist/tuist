import Basic
import Foundation

class GenerationOptions {
    let buildConfiguration: BuildConfiguration

    init(buildConfiguration: BuildConfiguration = .debug) {
        self.buildConfiguration = buildConfiguration
    }
}
