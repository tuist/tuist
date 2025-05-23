import Path
import TuistCore
import TuistSupport

@testable import TuistLoader

public class MockPackageSettingsLoader: PackageSettingsLoading {
    public init() {}

    public var invokedLoadPackageSettings = false
    public var invokedLoadPackageSettingsCount = 0
    public var invokedLoadPackageSettingsParameters: (AbsolutePath, Plugins, Bool)?
    public var invokedLoadPackageSettingsParemetersList = [(AbsolutePath, Plugins, Bool)]()
    public var loadPackageSettingsStub: ((AbsolutePath, Plugins, Bool) throws -> PackageSettings)?

    public func loadPackageSettings(
        at path: AbsolutePath,
        with plugins: Plugins,
        disableSandbox: Bool
    ) throws -> PackageSettings {
        invokedLoadPackageSettings = true
        invokedLoadPackageSettingsCount += 1
        invokedLoadPackageSettingsParameters = (path, plugins, disableSandbox)
        invokedLoadPackageSettingsParemetersList.append((path, plugins, disableSandbox))

        return try loadPackageSettingsStub?(path, plugins, disableSandbox) ?? PackageSettings.test()
    }
}
