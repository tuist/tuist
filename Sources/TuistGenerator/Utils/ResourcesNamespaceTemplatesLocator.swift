import TSCBasic
import TuistSupport

enum ResourcesNamespaceTemplatesError: FatalError {
    /// File at given path was not found
    case fileNotFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .fileNotFound:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "File \(path) doesn't exist."
        }
    }
}

protocol ResourcesNamespaceTemplatesLocating {
    func locateTemplate(for namespaceType: NamespaceType) throws -> AbsolutePath
}

final class ResourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating {
    func locateTemplate(for namespaceType: NamespaceType) throws -> AbsolutePath {
        let template = try locateResourcesNamespaceTemplatesDirectory().appending(component: namespaceType.templateFileName)
        guard
            FileHandler.shared.exists(template)
        else {
            throw ResourcesNamespaceTemplatesError.fileNotFound(template)
        }
        return template
    }

    // MARK: - Helpers

    private func locateResourcesNamespaceTemplatesDirectory() throws -> AbsolutePath {
        #if DEBUG
            // Used only for debug purposes to find templates in your tuist working directory
            // `bundlePath` points to tuist/ResourcesNamespaceTemplates
            let templatesPath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(component: "ResourcesNamespaceTemplates")
        #else
            let templatesPath = AbsolutePath(Bundle(for: ResourcesNamespaceTemplatesLocator.self).bundleURL.path)
                .appending(component: "ResourcesNamespaceTemplates")
        #endif
        guard
            FileHandler.shared.exists(templatesPath)
        else {
            throw ResourcesNamespaceTemplatesError.fileNotFound(templatesPath)
        }
        return templatesPath
    }
}
