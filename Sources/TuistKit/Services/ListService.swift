import Basic
import TuistSupport
import TuistLoader
import TuistScaffold
import Foundation

class ListService {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateLoader: TemplateLoading
    
    init(templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         templateLoader: TemplateLoading = TemplateLoader()) {
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateLoader = templateLoader
    }
    
    func run(path: String?) throws {
        let path = self.path(path)
        
        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)

        try templateDirectories.forEach {
            let template = try templateLoader.loadTemplate(at: $0)
            logger.info("\($0.basename): \(template.description)")
        }
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
