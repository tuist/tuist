import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

protocol TestServiceGeneratorFactorying {
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath
    ) -> Generating
}

final class TestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath
    ) -> Generating {
        Generator(
            projectMapperProvider: AutomationProjectMapperProvider(),
            graphMapperProvider: AutomationGraphMapperProvider(
                testsCacheDirectory: testsCacheDirectory
            ),
            workspaceMapperProvider: AutomationWorkspaceMapperProvider(
                workspaceDirectory: FileHandler.shared.resolveSymlinks(automationPath)
            ),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}
