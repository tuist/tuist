import Basic
import Foundation
import TuistSupport

public protocol TemplateHelpersDirectoryLocating {
    /// Returns the path to the helpers directory if it exists.
    /// - Parameter at: Path of template
    func locate(at: AbsolutePath) -> AbsolutePath?
}

public final class TemplateHelpersDirectoryLocator: TemplateHelpersDirectoryLocating {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    
    /// Default constructor.
    public init(templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator()) {
        self.templatesDirectoryLocator = templatesDirectoryLocator
    }

    // MARK: - TemplateHelpersDirectoryLocating

    public func locate(at: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = templatesDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.templateHelpersDirectoryName)
        if !FileHandler.shared.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}
