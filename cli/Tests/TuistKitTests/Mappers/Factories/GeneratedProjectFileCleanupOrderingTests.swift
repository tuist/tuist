import Testing
import TuistGenerator
@testable import TuistKit

struct GeneratedProjectFileCleanupOrderingTests {
    @Test func cleanupRunsAfterEveryPreservedFileGenerator() throws {
        let mappers = ProjectMapperFactory().default(tuist: .default)
        let cleanup = try #require(mappers.firstIndex { $0 is CleanGeneratedProjectFilesMapper })
        let generators = [
            try #require(mappers.firstIndex { $0 is SynthesizedResourceInterfaceProjectMapper }),
            try #require(mappers.firstIndex { $0 is ResourcesProjectMapper }),
            try #require(mappers.firstIndex { $0 is GenerateInfoPlistProjectMapper }),
            try #require(mappers.firstIndex { $0 is GenerateEntitlementsProjectMapper }),
        ]

        for generator in generators {
            #expect(generator < cleanup)
        }
    }
}
