import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A component responsible for converting Manifests (`ProjectDescription`) to Models (`TuistCore`)
public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) throws -> TuistGraph.Workspace
    func convert(manifest: ProjectDescription.Project, path: AbsolutePath) throws -> TuistGraph.Project
}
