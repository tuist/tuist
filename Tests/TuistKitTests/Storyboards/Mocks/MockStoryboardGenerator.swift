import Basic
import Foundation
@testable import TuistKit

final class MockStoryboardGenerator: StoryboardGenerating {
    typealias Storyboard = (path: AbsolutePath, name: String, platform: Platform, isLaunchScreen: Bool)

    var generatedStoryboards: [Storyboard] = []
    var generateStub: Error?

    func generate(path: AbsolutePath, name: String, platform: Platform, isLaunchScreen: Bool) throws {
        let storyboard = Storyboard(path, name, platform, isLaunchScreen)

        if !hasPreviouslyGenerated(storyboard) {
            generatedStoryboards.append(storyboard)
        } else {
            generateStub = "A\(storyboard.isLaunchScreen ? " Launch Screen storyboard" : "") with the name \(storyboard.name).storyboard for \(platform) was generated more than once."
        }

        if let generateStub = generateStub {
            throw generateStub
        }
    }

    func hasPreviouslyGenerated(_ storyboard: Storyboard) -> Bool {
        return generatedStoryboards.contains {
            $0.path == storyboard.path &&
                $0.name == storyboard.name &&
                $0.platform == storyboard.platform &&
                $0.isLaunchScreen == storyboard.isLaunchScreen
        }
    }
}
