import FileSystem
import FileSystemTesting
import Path
import ProjectDescription
import Testing
import XcodeGraph

@testable import TuistLoader

struct BuildActionManifestMapperTests {
    @Test(.inTemporaryDirectory)
    func mapsBuildForOptionsAndResolvesProjectPaths() throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifestDirectory = temporaryDirectory.appending(component: "App")
        let generatorPaths = GeneratorPaths(
            manifestDirectory: manifestDirectory,
            rootDirectory: temporaryDirectory
        )
        let manifest = ProjectDescription.BuildAction.buildAction(
            buildActionTargets: [
                .target("App", buildFor: [.running]),
                .project(
                    path: .relativeToManifest("../Feature"),
                    target: "Feature",
                    buildFor: [.testing]
                ),
            ]
        )

        let subject = try XcodeGraph.BuildAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        let appTarget = XcodeGraph.TargetReference(projectPath: manifestDirectory, name: "App")
        let featureTarget = XcodeGraph.TargetReference(
            projectPath: temporaryDirectory.appending(component: "Feature"),
            name: "Feature"
        )
        #expect(subject.targets == [appTarget, featureTarget])
        #expect(subject.buildFor[appTarget] == [.running])
        #expect(subject.buildFor[featureTarget] == [.testing])
    }
}
