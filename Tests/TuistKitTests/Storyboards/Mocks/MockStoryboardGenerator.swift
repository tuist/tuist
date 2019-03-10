import Basic
import Foundation
@testable import TuistKit

final class MockStoryboardGenerator: StoryboardGenerating {

    struct GeneratedStoryboard: Equatable {
        let path: AbsolutePath
        let name: String
        let platform: Platform
        let product: Product
        let isLaunchScreen: Bool
    }

    var generatedStoryboards: [GeneratedStoryboard] = []
    var generateStub: Error?

    func generate(path: AbsolutePath, name: String, platform: Platform, product: Product, isLaunchScreen: Bool) throws {
        let storyboard = GeneratedStoryboard(path: path,
                                             name: name,
                                             platform: platform,
                                             product: product,
                                             isLaunchScreen: isLaunchScreen)

        if !generatedStoryboards.contains(storyboard) {
            generatedStoryboards.append(storyboard)
        } else {
            generateStub = "A\(storyboard.isLaunchScreen ? " Launch Screen storyboard" : "") with the name \(storyboard.name).storyboard for \(platform) was generated more than once."
        }

        if let generateStub = generateStub {
            throw generateStub
        }
    }
}
