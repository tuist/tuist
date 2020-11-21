import Foundation
import TuistCore

@testable import TuistKit

final class MockProjectMapperProvider: ProjectMapperProviding {
    var mapperStub: ((Config) -> ProjectMapping)?
    func mapper(config: Config) -> ProjectMapping {
        mapperStub?(config) ?? SequentialProjectMapper(mappers: [])
    }
}
