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
        skipUITests: Bool
    ) -> Generating
}

final class TestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating {
        Generator(
            projectMapperProvider: AutomationProjectMapperProvider(skipUITests: skipUITests),
            graphMapperProvider: AutomationGraphMapperProvider(
                testsCacheDirectory: testsCacheDirectory
            ),
            workspaceMapperProvider: AutomationWorkspaceMapperProvider(
                workspaceDirectory: FileHandler.shared.resolveSymlinks(automationPath),
                skipUITests: skipUITests
            ),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}
