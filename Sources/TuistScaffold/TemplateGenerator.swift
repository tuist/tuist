import Foundation
import PathKit
import StencilSwiftKit
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Interface for generating content defined in template manifest
public protocol TemplateGenerating {
    /// Generate files for template manifest at `path`
    /// - Parameters:
    ///     - template: Template we are generating
    ///     - destinationPath: Path of directory where files should be generated to
    ///     - attributes: Attributes from user input
    func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: String]
    ) throws
}

public final class TemplateGenerator: TemplateGenerating {
    // Public initializer
    public init() {}

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: String]
    ) throws {
        let renderedItems = try renderItems(
            template: template,
            attributes: attributes
        )
        try generateDirectories(
            renderedItems: renderedItems,
            destinationPath: destinationPath
        )

        try generateItems(
            renderedItems: renderedItems,
            attributes: attributes,
            destinationPath: destinationPath
        )
    }

    // MARK: - Helpers

    /// Renders items' paths in format  path_to_dir/{{ attribute_name }} with `attributes`
    private func renderItems(
        template: Template,
        attributes: [String: String]
    ) throws -> [Template.Item] {
        try attributes.reduce(template.items) { items, attribute in
            try items.map {
                let path = RelativePath(
                    $0.path.pathString
                        .replacingOccurrences(of: "{{ \(attribute.key) }}", with: attribute.value)
                )

                var contents = $0.contents
                if case let Template.Contents.file(path) = contents {
                    contents = .file(
                        try AbsolutePath(
                            validating: path.pathString.replacingOccurrences(
                                of: "{{ \(attribute.key) }}", with: attribute.value
                            )
                        )
                    )
                }
                if case let Template.Contents.directory(path) = contents {
                    contents = .directory(
                        try AbsolutePath(
                            validating: path.pathString.replacingOccurrences(
                                of: "{{ \(attribute.key) }}", with: attribute.value
                            )
                        )
                    )
                }

                return Template.Item(path: path, contents: contents)
            }
        }
    }

    /// Generate all necessary directories
    private func generateDirectories(
        renderedItems: [Template.Item],
        destinationPath: AbsolutePath
    ) throws {
        try renderedItems
            .map(\.path)
            .map {
                destinationPath.appending(RelativePath($0.dirname))
            }
            .forEach {
                guard !FileHandler.shared.exists($0) else { return }
                try FileHandler.shared.createFolder($0)
            }
    }

    /// Generate all `renderedItems`
    private func generateItems(
        renderedItems: [Template.Item],
        attributes: [String: String],
        destinationPath: AbsolutePath
    ) throws {
        let environment = stencilSwiftEnvironment()
        try renderedItems.forEach {
            let renderedContents: String?
            switch $0.contents {
            case let .string(contents):
                renderedContents = try environment.renderTemplate(
                    string: contents,
                    context: attributes
                )
            case let .file(path):
                let injectedLoaderEnvironment = stencilSwiftEnvironment(templatePaths: [Path(path.dirname)])
                let fileContents = try FileHandler.shared.readTextFile(path)
                // Render only files with .stencil extension
                if path.extension == "stencil" {
                    renderedContents = try injectedLoaderEnvironment.renderTemplate(
                        string: fileContents,
                        context: attributes
                    )
                } else {
                    renderedContents = fileContents
                }
            case let .directory(path):
                let destinationDirectoryPath = destinationPath
                    .appending(RelativePath($0.path.pathString))
                    .appending(component: path.basename)
                // workaround for creating folder tree of destinationDirectoryPath
                if !FileHandler.shared.exists(destinationDirectoryPath.parentDirectory) {
                    try FileHandler.shared.createFolder(destinationDirectoryPath.parentDirectory)
                }
                if FileHandler.shared.exists(destinationDirectoryPath) {
                    try FileHandler.shared.delete(destinationDirectoryPath)
                }
                try FileHandler.shared.copy(from: path, to: destinationDirectoryPath)
                renderedContents = nil
            }
            // Generate file only when it has some content
            guard let rendered = renderedContents,
                  !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try FileHandler.shared.write(
                rendered,
                path: destinationPath.appending($0.path),
                atomically: true
            )
        }
    }
}
