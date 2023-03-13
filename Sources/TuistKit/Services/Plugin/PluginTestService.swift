import TSCBasic
import TuistSupport

final class PluginTestService {
    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        testProducts: [String]
    ) throws {
        var testCommand = [
            "swift", "test",
            "--configuration", configuration.rawValue,
        ]
        if let path = path {
            testCommand += [
                "--package-path",
                try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath).pathString,
            ]
        }
        if buildTests {
            testCommand.append(
                "--build-tests"
            )
        }
        testProducts.forEach {
            testCommand += [
                "--test-product", $0,
            ]
        }
        try System.shared.runAndPrint(testCommand)
    }
}
