import PathKit
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistSupport

enum SynthesizedResourceInterfaceType {
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
    
    fileprivate func parser() throws -> Parser {
        switch self {
        case .assets:
            return try AssetsCatalog.Parser()
        case .strings:
            return try Strings.Parser()
        }
    }
}

protocol SynthesizedResourceInterfacesGenerating {
    func render(_ namespaceType: SynthesizedResourceInterfaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)]
    func generateNamespaceScript() -> String
}

final class SynthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating {
    private let resourcesNamespaceTemplatesLocator: SynthesizedResourceInterfaceLocating

    init(
        resourcesNamespaceTemplatesLocator: SynthesizedResourceInterfaceLocating = SynthesizedResourceInterfaceTemplatesLocator()
    ) {
        self.resourcesNamespaceTemplatesLocator = resourcesNamespaceTemplatesLocator
    }

    func render(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        paths: [AbsolutePath]
    ) throws -> [(name: String, contents: String)] {
        let templatePath = try resourcesNamespaceTemplatesLocator.locateTemplate(for: synthesizedResourceInterfaceType)
        let template = StencilSwiftTemplate(
            templateString: try FileHandler.shared.readTextFile(templatePath),
            environment: stencilSwiftEnvironment()
        )

        return try paths.map { path in
            let parser = try synthesizedResourceInterfaceType.parser()
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
