import PathKit
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistSupport

enum NamespaceType {
    case assets
    case strings

    var templateFileName: String {
        switch self {
        case .assets:
            return "xcassets.stencil"
        case .strings:
            return "strings.stencil"
        }
    }
}

private extension NamespaceType {
    func parser() throws -> Parser {
        switch self {
        case .assets:
            return try AssetsCatalog.Parser()
        case .strings:
            return try Strings.Parser()
        }
    }
}

protocol NamespaceGenerating {
    func render(_ namespaceType: NamespaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)]
    func generateNamespaceScript() -> String
}

final class NamespaceGenerator: NamespaceGenerating {
    private let resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating

    init(
        resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating = ResourcesNamespaceTemplatesLocator()
    ) {
        self.resourcesNamespaceTemplatesLocator = resourcesNamespaceTemplatesLocator
    }

    func render(_ namespaceType: NamespaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)] {
        let templatePath = try resourcesNamespaceTemplatesLocator.locateTemplate(for: namespaceType)
        let template = StencilSwiftTemplate(
            templateString: try FileHandler.shared.readTextFile(templatePath),
            environment: stencilSwiftEnvironment()
        )

        return try paths.map { path in
            let parser = try namespaceType.parser()
            try parser.parse(path: Path(path.pathString), relativeTo: Path(""))
            var context = parser.stencilContext()
            context = try StencilContext.enrich(context: context, parameters: ["publicAccess": true])
            return (path.basenameWithoutExt, try template.render(context))
        }
    }

    func generateNamespaceScript() -> String {
        #if DEBUG
            // Used only for debug purposes to find currently-built tuist
            // `bundlePath` points to .build/debug/tuist
            let tuistCommand = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(components: ".build", "debug", "tuist")
                .pathString
        #else
            let tuistCommand = "tuist"
        #endif
        return """
        #!/bin/sh

        pushd "${SRCROOT}"
        \(tuistCommand) generate namespace
        popd
        """
    }
}
