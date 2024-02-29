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
        if let path {
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
        for testProduct in testProducts {
            testCommand += [
                "--test-product", testProduct,
            ]
        }
        try System.shared.runAndPrint(testCommand)
    }
}
