import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.MetalOptions {
    static func from(manifest: ProjectDescription.MetalOptions) -> XcodeGraph.MetalOptions {
        return XcodeGraph.MetalOptions(
            apiValidation: manifest.apiValidation,
            shaderValidation: manifest.shaderValidation,
            showGraphicsOverview: manifest.showGraphicsOverview,
            logGraphicsOverview: manifest.logGraphicsOverview
        )
    }
}
