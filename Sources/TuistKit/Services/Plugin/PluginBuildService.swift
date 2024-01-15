import TSCBasic
import TuistSupport

final class PluginBuildService {
    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        showBinPath: Bool,
        targets: [String],
        products: [String]
    ) throws {
        var buildCommand = [
            "swift", "build",
            "--configuration", configuration.rawValue,
        ]
        if let path {
            buildCommand += [
                "--package-path",
                path,
            ]
        }
        if buildTests {
            buildCommand.append(
                "--build-tests"
            )
        }
        if showBinPath {
            buildCommand.append(
                "--show-bin-path"
            )
        }
        for target in targets {
            buildCommand += [
                "--target", target,
            ]
        }
        for product in products {
            buildCommand += [
                "--product", product,
            ]
        }
        try System.shared.runAndPrint(buildCommand)
    }
}
