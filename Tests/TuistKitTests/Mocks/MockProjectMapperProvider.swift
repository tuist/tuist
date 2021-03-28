import Foundation
import TuistCore
import TuistGraph

@testable import TuistKit

final class MockProjectMapperProvider: ProjectMapperProviding {
    var mapperStub: ((Config, Plugins) -> ProjectMapping)?
    func mapper(
        config: Config,
        plugins: Plugins
    ) -> ProjectMapping {
        mapperStub?(config, plugins) ?? SequentialProjectMapper(mappers: [])
    }
}
