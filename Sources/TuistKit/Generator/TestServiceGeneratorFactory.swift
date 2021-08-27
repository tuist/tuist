import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

protocol TestServiceGeneratorFactorying {
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool,
        skipCache: Bool
    ) -> Generating
}

final class TestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool,
        skipCache: Bool
    ) -> Generating {
        Generator(
            projectMapperProvider: AutomationProjectMapperProvider(skipUITests: skipUITests),
            graphMapperProvider: AutomationGraphMapperProvider(
                testsCacheDirectory: testsCacheDirectory,
                skipTestsCache: skipCache
            ),
            workspaceMapperProvider: AutomationWorkspaceMapperProvider(
                workspaceDirectory: FileHandler.shared.resolveSymlinks(automationPath),
                skipUITests: skipUITests
            ),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}
