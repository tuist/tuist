import FileSystem
import Foundation
import Mockable
import Path
import PathKit
import StencilSwiftKit
import TuistCore
import TuistSupport

/// Interface for generating content defined in template manifest
@Mockable
public protocol TemplateGenerating {
    /// Generate files for template manifest at `path`
    /// - Parameters:
    ///     - template: Template we are generating
    ///     - destinationPath: Path of directory where files should be generated to
    ///     - attributes: Attributes from user input
    func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: Template.Attribute.Value]
    ) async throws
}

public final class TemplateGenerator: TemplateGenerating {
    private let fileSystem: FileSystem

    // Public initializer

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: Template.Attribute.Value]
    ) async throws {
        let renderedItems = try renderItems(
            template: template,
            attributes: attributes
        )
        try await generateDirectories(
            renderedItems: renderedItems,
            destinationPath: destinationPath
        )

        try await generateItems(
            renderedItems: renderedItems,
            attributes: attributes,
            destinationPath: destinationPath
        )
    }

    // MARK: - Helpers

    /// Renders items' paths in format  path_to_dir/{{ attribute_name }} with `attributes`
    private func renderItems(
        template: Template,
        attributes: [String: Template.Attribute.Value]
    ) throws -> [Template.Item] {
        let environment = stencilSwiftEnvironment()
        return try template.items.map {
            let renderedPathString = try environment.renderTemplate(
                string: $0.path.pathString,
                context: attributes.toStringAny
            )
            let path = try RelativePath(validating: renderedPathString)

            var contents = $0.contents
            if case let Template.Contents.file(path) = contents {
                let renderedPathString = try environment.renderTemplate(
                    string: path.pathString,
                    context: attributes.toStringAny
                )
                contents = .file(
                    try AbsolutePath(validating: renderedPathString)
                )
            }
            if case let Template.Contents.directory(path) = contents {
                let renderedPathString = try environment.renderTemplate(
                    string: path.pathString,
                    context: attributes.toStringAny
                )
                contents = .directory(
                    try AbsolutePath(validating: renderedPathString)
                )
            }

            return Template.Item(path: path, contents: contents)
        }
    }

    /// Generate all necessary directories
    private func generateDirectories(
        renderedItems: [Template.Item],
        destinationPath: AbsolutePath
    ) async throws {
        for item in try renderedItems
            .map(\.path)
            .map({
                destinationPath.appending(try RelativePath(validating: $0.dirname))
            })
        {
            guard try await !fileSystem.exists(item) else { return }
            try await fileSystem.makeDirectory(at: item)
        }
    }

    /// Generate all `renderedItems`
    private func generateItems(
        renderedItems: [Template.Item],
        attributes: [String: Template.Attribute.Value],
        destinationPath: AbsolutePath
    ) async throws {
        let environment = stencilSwiftEnvironment()
        for renderedItem in renderedItems {
            let renderedContents: String?
            switch renderedItem.contents {
            case let .string(contents):
                renderedContents = try environment.renderTemplate(
                    string: contents,
                    context: attributes.toStringAny
                )
            case let .file(path):
                let injectedLoaderEnvironment = stencilSwiftEnvironment(templatePaths: [Path(path.dirname)])
                let fileContents = try FileHandler.shared.readTextFile(path)
                // Render only files with .stencil extension
                if path.extension == "stencil" {
                    renderedContents = try injectedLoaderEnvironment.renderTemplate(
                        string: fileContents,
                        context: attributes.toStringAny
                    )
                } else {
                    renderedContents = fileContents
                }
            case let .directory(path):
                let destinationDirectoryPath = destinationPath
                    .appending(try RelativePath(validating: renderedItem.path.pathString))
                    .appending(component: path.basename)
                // workaround for creating folder tree of destinationDirectoryPath
                if try await !fileSystem.exists(destinationDirectoryPath.parentDirectory) {
                    try await fileSystem.makeDirectory(at: destinationDirectoryPath.parentDirectory)
                }
                if try await fileSystem.exists(destinationDirectoryPath) {
                    try await fileSystem.remove(destinationDirectoryPath)
                }
                try await fileSystem.copy(path, to: destinationDirectoryPath)
                renderedContents = nil
            }
            // Generate file only when it has some content, unless it is a `.gitkeep` file
            if let rendered = renderedContents,
               !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               renderedItem.path.basename == ".gitkeep"
            {
                let contentsPath = destinationPath.appending(renderedItem.path)
                if try await !fileSystem.exists(contentsPath.parentDirectory) {
                    try await fileSystem.makeDirectory(at: contentsPath.parentDirectory)
                }
                try await fileSystem.writeText(
                    rendered,
                    at: destinationPath.appending(renderedItem.path)
                )
            }
        }
    }
}

extension [String: Template.Attribute.Value] {
    fileprivate var toStringAny: [String: Any] {
        reduce([:]) { partialResult, attribute in
            var result: [String: Any] = partialResult
            result[attribute.key] = attribute.value.rawValue
            return result
        }
    }
}
