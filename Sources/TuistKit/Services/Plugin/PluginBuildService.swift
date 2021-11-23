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
        if let path = path {
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
        targets.forEach {
            buildCommand += [
                "--target", $0,
            ]
        }
        products.forEach {
            buildCommand += [
                "--product", $0,
            ]
        }
        try System.shared.runAndPrint(buildCommand)
    }
}
