import Foundation
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

extension DotGraphGenerating {
    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project.
    ///   - manifestLoader: Instance to load the manifest.
    ///   - skipTestTargets: Excluldes test targets from the graph.
    ///   - skipExternalDependencies: Excluldes external dependencies  from the graph.
    /// - Returns: Dot graph in png data represetation.
    /// - Throws: An error if the manifest can't be loaded.
    func generate(at path: AbsolutePath,
                  manifestLoader: ManifestLoading,
                  skipTestTargets: Bool,
                  skipExternalDependencies: Bool) throws -> Data
    {
        let manifests = manifestLoader.manifests(at: path)

        if try !isGraphvizInstalled() {
            try installGraphviz()
        }

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    // MARK: - Privates

    /// Checks whether graphviz is installed or not.
    ///
    /// - Returns: Bool representing graphviz package presence.
    /// - Throws: An error if the 'brew  list' command errors out.
    private func isGraphvizInstalled() throws -> Bool {
        try System.shared.capture(["brew", "list"]).contains("graphviz")
    }

    /// Install graphviz package through HomeBrew.
    ///
    /// - Throws: An error if the 'brew  install graphviz' command errors out.
    private func installGraphviz() throws {
        logger.notice("Installing graphviz...")
        var env = System.shared.env
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}
