import Foundation
import TSCBasic
import TuistLoader
import TuistScaffold
import TuistSupport

class ListService {
    // MARK: - OutputFormat

    enum OutputFormat {
        case table
        case json
    }

    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateLoader: TemplateLoading

    init(templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         templateLoader: TemplateLoading = TemplateLoader())
    {
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateLoader = templateLoader
    }

    func run(path: String?, outputFormat format: OutputFormat) throws {
        let path = self.path(path)

        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)
        let templates: [PrintableTemplate] = try templateDirectories.map { path in
            let template = try templateLoader.loadTemplate(at: path)
            return PrintableTemplate(name: path.basename, description: template.description)
        }

        let output = try string(for: templates, in: format)
        logger.info("\(output)")
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func string(for templates: [PrintableTemplate],
                        in format: ListService.OutputFormat) throws -> String
    {
        switch format {
        case .table:
            let textTable = TextTable<PrintableTemplate> { [
                TextTable.Column(title: "Name", value: $0.name),
                TextTable.Column(title: "Description", value: $0.description),
            ] }
            return textTable.render(templates)

        case .json:
            let json = try templates.toJSON()
            return json.toString(prettyPrint: true)
        }
    }
}

private struct PrintableTemplate: Codable {
    let name: String
    let description: String
}
