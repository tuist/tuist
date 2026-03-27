import Path
import TuistEnvironment
import TuistSupport

struct PluginTestService {
    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        testProducts: [String]
    ) async throws {
        var testCommand = [
            "swift", "test",
            "--configuration", configuration.rawValue,
        ]
        if let path {
            testCommand += [
                "--package-path",
                try await Environment.current.pathRelativeToWorkingDirectory(path).pathString,
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
