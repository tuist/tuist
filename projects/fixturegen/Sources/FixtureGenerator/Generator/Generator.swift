import Foundation
import TSCBasic

class Generator {
    private let fileSystem: FileSystem
    private let config: GeneratorConfig
    private let sourceTemplate: SourceTemplate
    private let manifestTemplate: ManifestTemplate

    init(fileSystem: FileSystem, config: GeneratorConfig) {
        self.fileSystem = fileSystem
        self.config = config

        sourceTemplate = SourceTemplate()
        manifestTemplate = ManifestTemplate()
    }

    func generate(at path: AbsolutePath) throws {
        let rootPath = path
        let projects = (1 ... config.projects).map { "Project\($0)" }

        try fileSystem.createDirectory(rootPath)
        try initWorkspaceManifest(
            at: rootPath,
            name: "Workspace",
            projects: projects
        )

        try projects.forEach {
            try initProject(
                at: rootPath,
                name: $0
            )
        }
    }

    private func initWorkspaceManifest(
        at path: AbsolutePath,
        name: String,
        projects: [String]
    ) throws {
        let manifestPath = path.appending(component: "Workspace.swift")

        let manifest = manifestTemplate.generate(
            workspaceName: name,
            projects: projects
        )
        try fileSystem.writeFileContents(
            manifestPath,
            bytes: ByteString(encodingAsUTF8: manifest)
        )
    }

    private func initProject(
        at path: AbsolutePath,
        name: String
    ) throws {
        let projectPath = path.appending(component: name)
        let targets = (1 ... config.targets).map { "Target\($0)" }

        try fileSystem.createDirectory(projectPath)
        try initProjectManifest(at: projectPath, name: name, targets: targets)

        try targets.forEach {
            try initTarget(at: projectPath, name: $0)
        }
    }

    private func initProjectManifest(
        at path: AbsolutePath,
        name: String,
        targets: [String]
    ) throws {
        let manifestPath = path.appending(component: "Project.swift")

        let manifest = manifestTemplate.generate(
            projectName: name,
            targets: targets
        )
        try fileSystem.writeFileContents(
            manifestPath,
            bytes: ByteString(encodingAsUTF8: manifest)
        )
    }

    private func initTarget(at path: AbsolutePath, name: String) throws {
        let targetPath = path.appending(component: name)

        try fileSystem.createDirectory(targetPath)
        try initSources(at: targetPath, targetName: name)
    }

    private func initSources(at path: AbsolutePath, targetName: String) throws {
        let sourcesPath = path.appending(component: "Sources")

        try fileSystem.createDirectory(sourcesPath)
        try (1 ... config.sources).forEach {
            let sourceName = "Source\($0).swift"
            let source = sourceTemplate.generate(frameworkName: targetName, number: $0)
            try fileSystem.writeFileContents(
                sourcesPath.appending(component: sourceName),
                bytes: ByteString(encodingAsUTF8: source)
            )
        }
    }
}
