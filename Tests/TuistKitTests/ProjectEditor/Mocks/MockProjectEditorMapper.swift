import Foundation
import TSCBasic
import TuistCore

@testable import TuistCoreTesting
@testable import TuistKit

final class MockProjectEditorMapper: ProjectEditorMapping {
    var mapStub: (Project, Graph)?
    var mapArgs: [(
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        manifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    )] = []

    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) -> (Project, Graph) {
        mapArgs.append((tuistPath: tuistPath,
                        sourceRootPath: sourceRootPath,
                        manifests: manifests,
                        helpers: helpers,
                        templates: templates,
                        projectDescriptionPath: projectDescriptionPath))
        if let mapStub = mapStub { return mapStub }
        return (Project.test(), Graph.test())
    }
}
