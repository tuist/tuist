import Foundation
import TuistCore
import TuistGraph

@testable import TuistKit

final class MockWorkspaceMapperProvider: WorkspaceMapperProviding {
    var mapperStub: ((Config, Plugins) -> WorkspaceMapping)?
    func mapper(
        config: Config,
        plugins: Plugins
    ) -> WorkspaceMapping {
        mapperStub?(config, plugins) ?? SequentialWorkspaceMapper(mappers: [])
    }
}
