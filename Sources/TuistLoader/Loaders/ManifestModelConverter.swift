import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

/// A component responsible for converting Manifests (`ProjectDescription`) to Models (`TuistCore`)
public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) throws -> TuistCore.Workspace
    func convert(manifest: ProjectDescription.Project, path: AbsolutePath) throws -> TuistCore.Project
    func convert(manifest: ProjectDescription.Config, path: AbsolutePath) throws -> TuistCore.Config
    func convert(manifest: ProjectDescription.Plugin) throws -> TuistCore.Plugin
}
