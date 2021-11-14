import TuistSupport
import TSCBasic

final class PluginBuildService {
    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        showBinPath: Bool,
        target: String?,
        product: String?
    ) throws {
        var buildCommand = [
            "swift", "build",
            "--configuration", configuration.rawValue
        ]
        if let path = path {
            buildCommand += [
                "--package-path",
                AbsolutePath(path, relativeTo: FileHandler.shared.currentPath).pathString
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
        if let target = target {
            buildCommand += [
                "--target", target,
            ]
        }
        if let product = product {
            buildCommand += [
                "--product", product
            ]
        }
        try System.shared.runAndPrint(buildCommand)
    }
}
