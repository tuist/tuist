import Foundation
import Mockable
import TuistCore
import TuistServer
import XcodeGraph

/// The protocol describes the interface of a factory that instantiates
/// generators for different commands
@Mockable
public protocol GeneratorFactorying {
    /// Returns the generator to generate a project to run tests on.
    /// - Parameter config: The project configuration
    /// - Parameter skipUITests: Whether UI tests should be skipped.
    /// - Parameter skipUnitTests: Whether Unit tests should be skipped.
    /// - Parameter ignoreBinaryCache: True to not include binaries from the cache.
    /// - Parameter ignoreSelectiveTesting: True to run all tests
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: A Generator instance.
    func testing(
        config: Tuist,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        skipUnitTests: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        ignoreSelectiveTesting: Bool,
        cacheStorage: CacheStoring,
        destination: SimulatorDeviceAndRuntime?
    ) -> Generating

    /// Returns the generator for focused projects.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The list of targets whose sources should be included.
    /// - Parameter configuration: The configuration to generate for.
    /// - Parameter cacheProfile: Cache profile to use for binary replacement.
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: The generator for focused projects.
    func generation(
        config: Tuist,
        includedTargets: Set<TargetQuery>,
        configuration: String?,
        cacheProfile: CacheProfile,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns a generator for building a project.
    /// - Parameters:
    ///     - config: The project configuration.
    ///     - configuration: The configuration to build for.
    ///     - ignoreBinaryCache: True to not include binaries from the cache.
    ///     - cacheStorage: The cache storage instance.
    /// - Returns: A Generator instance.
    func building(
        config: Tuist,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The list of targets whose sources should be included.
    /// - Returns: A Generator instance.
    func defaultGenerator(
        config: Tuist,
        includedTargets: Set<TargetQuery>
    ) -> Generating
}

/// An empty generator factory that does nothing. Used as a default value.
public struct EmptyGeneratorFactory: GeneratorFactorying {
    public init() {}

    public func testing(
        config _: Tuist,
        testPlan _: String?,
        includedTargets _: Set<String>,
        excludedTargets _: Set<String>,
        skipUITests _: Bool,
        skipUnitTests _: Bool,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        ignoreSelectiveTesting _: Bool,
        cacheStorage _: CacheStoring,
        destination _: SimulatorDeviceAndRuntime?
    ) -> Generating {
        fatalError("GeneratorFactory not configured")
    }

    public func generation(
        config _: Tuist,
        includedTargets _: Set<TargetQuery>,
        configuration _: String?,
        cacheProfile _: CacheProfile,
        cacheStorage _: CacheStoring
    ) -> Generating {
        fatalError("GeneratorFactory not configured")
    }

    public func building(
        config _: Tuist,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        cacheStorage _: CacheStoring
    ) -> Generating {
        fatalError("GeneratorFactory not configured")
    }

    public func defaultGenerator(
        config _: Tuist,
        includedTargets _: Set<TargetQuery>
    ) -> Generating {
        fatalError("GeneratorFactory not configured")
    }
}
