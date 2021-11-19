import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public class PlayGraphMapper: GraphMapping {
    let temporaryDirectory: AbsolutePath
    let targetName: String

    public init(targetName: String, temporaryDirectory: AbsolutePath) {
        self.targetName = targetName
        self.temporaryDirectory = temporaryDirectory
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        var graph = graph
        graph.workspace.xcWorkspacePath = temporaryDirectory.appending(component: graph.workspace.xcWorkspacePath.basename)
        graph.projects = graph.projects.reduce(into: [AbsolutePath: Project]()) { projects, value in
            var project = value.value
            let mappedXcodeProjPath = temporaryDirectory.appending(component: project.xcodeProjPath.basename)
            project.xcodeProjPath = mappedXcodeProjPath
            projects[value.key] = project
        }

        let target = graph.targets.values.flatMap { $0.values }.first(where: { $0.name == targetName })
        let targetPlatform = target!.platform.rawValue

        let playgroundPath = temporaryDirectory.appending(component: "\(targetName).playground")
        graph.workspace = graph.workspace.adding(files: [playgroundPath])

        let contentXCPlaygroundPath = playgroundPath.appending(component: "contents.xcplayground")
        let contentsSwiftPath = playgroundPath.appending(component: "Contents.swift")

        guard let document = makePlaygroundDocument(using: targetPlatform) else {
            return (graph, [])
        }
        let documentContent = makePlaygroundContent()

        var sideEffects: [SideEffectDescriptor] = []
        sideEffects.append(.directory(.init(path: playgroundPath, state: .present)))
        sideEffects.append(.file(.init(path: contentXCPlaygroundPath, contents: document.xmlData, state: .present)))
        sideEffects.append(.file(.init(path: contentsSwiftPath, contents: documentContent.data(using: .utf8), state: .present)))

        return (graph, sideEffects)
    }
}

private extension PlayGraphMapper {
    func makePlaygroundDocument(using platform: String) -> XMLDocument? {
        let playground = XMLElement(name: "playground")
        guard let versionAttribute = XMLNode.attribute(withName: "version", stringValue: "5.0") as? XMLNode,
            let platformAttribute = XMLNode.attribute(withName: "target-platform", stringValue: "\(platform)") as? XMLNode,
            let activeSchemeAttribute = XMLNode.attribute(withName: "buildActiveScheme", stringValue: "true") as? XMLNode,
            let executeAttribute = XMLNode.attribute(withName: "executeOnSourceChanges", stringValue: "false") as? XMLNode,
            let appTypesAttribute = XMLNode.attribute(withName: "importAppTypes", stringValue: "true") as? XMLNode,
            let filenameAttribute = XMLNode.attribute(withName: "fileName", stringValue: "timeline.xctimeline") as? XMLNode
        else { return nil }

        playground.addAttribute(versionAttribute)
        playground.addAttribute(platformAttribute)
        playground.addAttribute(activeSchemeAttribute)
        playground.addAttribute(executeAttribute)
        playground.addAttribute(appTypesAttribute)
        let timeline = XMLElement(name: "timeline")
        timeline.addAttribute(filenameAttribute)
        playground.addChild(timeline)
        let document = XMLDocument(rootElement: playground)
        document.characterEncoding = "UTF-8"
        document.isStandalone = true
        document.version = "1.0"
        return document
    }

    func makePlaygroundContent() -> String {
        """
        import Foundation
        import \(targetName)

        print("Hello \(targetName)")
        """
    }
}
