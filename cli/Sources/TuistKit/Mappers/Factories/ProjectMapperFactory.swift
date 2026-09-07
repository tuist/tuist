import Foundation
import Path
import TuistAutomation
import TuistConfig
import TuistCore
import TuistDependencies
import TuistEnvironment
import TuistGenerator
import TuistGraphLoader
import TuistLoader
import TuistServer
import TuistSupport

/// The protocol describes an interface for getting project mappers.
protocol ProjectMapperFactorying {
    /// Returns the default project mapper.
    /// - Parameter config: The project configuration
    /// - Returns: A project mapper instance.
    func `default`(
        tuist: Tuist
    ) -> [ProjectMapping]

    /// Returns a project mapper for automation.
    /// - Parameter config: The project configuration.
    /// - Parameter skipUITests: Whether UI tests should be skipped.
    /// - Parameter skipUnitTests: Whether Unit tests should be skipped.
    /// - Returns: An instance of a project mapper.
    func automation(
        skipUITests: Bool,
        skipUnitTests: Bool,
        tuist: Tuist
    ) -> [ProjectMapping]
}

public struct ProjectMapperFactory: ProjectMapperFactorying {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    public func automation(
        skipUITests: Bool,
        skipUnitTests: Bool,
        tuist: Tuist
    ) -> [ProjectMapping] {
        var mappers: [ProjectMapping] = []
        mappers += self.default(tuist: tuist)
        if skipUITests {
            mappers.append(
                SkipUITestsProjectMapper()
            )
        }

        if skipUnitTests {
            mappers.append(
                SkipUnitTestsProjectMapper()
            )
        }

        return mappers
    }

    public func `default`(
        tuist: Tuist
    ) -> [ProjectMapping] {
        DefaultProjectMapperFactory(contentHasher: contentHasher).make(tuist: tuist)
    }
}
