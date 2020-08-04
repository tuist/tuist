import Foundation
import struct Stencil.Environment
import TSCBasic
import TuistCore
import TuistSupport

/// Interface for generating content defined in template manifest
public protocol TemplateGenerating {
    /// Generate files for template manifest at `path`
    /// - Parameters:
    ///     - template: Template we are generating
    ///     - destinationPath: Path of directory where files should be generated to
    ///     - attributes: Attributes from user input
    func generate(template: Template,
                  to destinationPath: AbsolutePath,
                  attributes: [String: String]) throws
}

public final class TemplateGenerator: TemplateGenerating {
    // Public initializer
    public init() {}

    public func generate(template: Template,
                         to destinationPath: AbsolutePath,
                         attributes: [String: String]) throws
    {
        let renderedFiles = renderFiles(template: template,
                                        attributes: attributes)
        try generateDirectories(renderedFiles: renderedFiles,
                                destinationPath: destinationPath)

        try generateFiles(renderedFiles: renderedFiles,
                          attributes: attributes,
                          destinationPath: destinationPath)
    }

    // MARK: - Helpers

    /// Renders files' paths in format  path_to_dir/{{ attribute_name }} with `attributes`
    private func renderFiles(template: Template,
                             attributes: [String: String]) -> [Template.File]
    {
        attributes.reduce(template.files) { files, attribute in
            files.map {
                let path = RelativePath($0.path.pathString.replacingOccurrences(of: "{{ \(attribute.key) }}", with: attribute.value))
                return Template.File(path: path, contents: $0.contents)
            }
        }
    }

    /// Generate all necessary directories
    private func generateDirectories(renderedFiles: [Template.File],
                                     destinationPath: AbsolutePath) throws
    {
        try renderedFiles
            .map(\.path)
            .map {
                destinationPath.appending(RelativePath($0.dirname))
            }
            .forEach {
                guard !FileHandler.shared.exists($0) else { return }
                try FileHandler.shared.createFolder($0)
            }
    }

    /// Generate all `renderedFiles`
    private func generateFiles(renderedFiles: [Template.File],
                               attributes: [String: String],
                               destinationPath: AbsolutePath) throws
    {
        let environment = Environment()
        try renderedFiles.forEach {
            let renderedContents: String
            switch $0.contents {
            case let .string(contents):
                renderedContents = try environment.renderTemplate(string: contents,
                                                                  context: attributes)
            case let .file(path):
                let fileContents = try FileHandler.shared.readTextFile(path)
                // Render only files with .stencil extension
                if path.extension == "stencil" {
                    renderedContents = try environment.renderTemplate(string: fileContents,
                                                                      context: attributes)
                } else {
                    renderedContents = fileContents
                }
            }
            // Generate file only when it has some content
            guard !renderedContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try FileHandler.shared.write(renderedContents,
                                         path: destinationPath.appending($0.path),
                                         atomically: true)
        }
    }
}
