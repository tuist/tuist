import Foundation
import TSCBasic
import TuistLoader
import TuistScaffold
import TuistSupport

class ListService {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateLoader: TemplateLoading
    private let textTable = TextTable<PrintableTemplate> { [
        TextTable.Column(title: "Name", value: $0.name),
        TextTable.Column(title: "Description", value: $0.description),
    ] }

    init(templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         templateLoader: TemplateLoading = TemplateLoader()) {
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateLoader = templateLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)

        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)
        let templates: [PrintableTemplate] = try templateDirectories.map { path in
            let template = try templateLoader.loadTemplate(at: path)
            return PrintableTemplate(name: path.basename, description: template.description)
        }

        let renderedTable = textTable.render(templates)
        logger.info("\(renderedTable)")
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}

private struct PrintableTemplate {
    let name: String
    let description: String
}
