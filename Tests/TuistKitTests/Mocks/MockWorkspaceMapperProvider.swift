import Foundation
import TuistCore

@testable import TuistKit

final class MockWorkspaceMapperProvider: WorkspaceMapperProviding {
    var mapperStub: ((Config) -> WorkspaceMapping)?
    func mapper(config: Config) -> WorkspaceMapping {
        mapperStub?(config) ?? SequentialWorkspaceMapper(mappers: [])
    }
}
