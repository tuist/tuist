import ProjectDescription
import TuistGraph

extension TuistGraph.TextSettings {
    /// Maps a ProjectDescription.TextSettings instance into a TuistGraph.TextSettings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of text settings.
    static func from(manifest: ProjectDescription.TextSettings) -> TuistGraph.TextSettings {
        TuistGraph.TextSettings(
            usesTabs: manifest.usesTabs,
            indentWidth: manifest.indentWidth,
            tabWidth: manifest.tabWidth,
            wrapsLines: manifest.wrapsLines
        )
    }
}
