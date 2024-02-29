import TSCBasic
import TuistGraph
import TuistGraphTesting
import TuistSupport

@testable import TuistLoader

public class MockPackageSettingsLoader: PackageSettingsLoading {
    public init() {}

    public var invokedLoadPackageSettings = false
    public var invokedLoadPackageSettingsCount = 0
    public var invokedLoadPackageSettingsParameters: (AbsolutePath, Plugins)?
    public var invokedLoadPackageSettingsParemetersList = [(AbsolutePath, Plugins)]()
    public var loadPackageSettingsStub: ((AbsolutePath, Plugins) throws -> PackageSettings)?

    public func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) throws -> PackageSettings {
        invokedLoadPackageSettings = true
        invokedLoadPackageSettingsCount += 1
        invokedLoadPackageSettingsParameters = (path, plugins)
        invokedLoadPackageSettingsParemetersList.append((path, plugins))

        return try loadPackageSettingsStub?(path, plugins) ?? PackageSettings.test()
    }
}
