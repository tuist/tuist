import Basic
import Foundation
@testable import TuistKit

final class MockStoryboardGenerator: StoryboardGenerating {
    struct GeneratedStoryboard: Equatable {
        let path: AbsolutePath
        let name: String
        let platform: Platform
        let product: Product?
    }

    var generatedStoryboards: [GeneratedStoryboard] = []
    var generateStub: Error?

    func generateMain(path: AbsolutePath, platform: Platform) throws {
        let storyboard = GeneratedStoryboard(path: path,
                                             name: "Main.storyboard",
                                             platform: platform,
                                             product: nil)
        try check(for: storyboard)
    }

    func generateLaunchScreen(path: AbsolutePath, platform: Platform, product: Product) throws {
        let storyboard = GeneratedStoryboard(path: path,
                                             name: "Launch Screen.storyboard",
                                             platform: platform,
                                             product: product)
        try check(for: storyboard)
    }

    private func check(for storyboard: GeneratedStoryboard) throws {
        if generatedStoryboards.contains(storyboard) {
            generateStub = "A storyboard with the name \(storyboard.name) for \(storyboard.platform) was generated more than once."
        }

        generatedStoryboards.append(storyboard)

        if let generateStub = generateStub {
            throw generateStub
        }
    }
}
