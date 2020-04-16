import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) throws -> TuistCore.Workspace
    func convert(manifest: ProjectDescription.Project, path: AbsolutePath) throws -> TuistCore.Project
}
