import TSCBasic
import TuistSupport

enum SynthesizedResourceInterfaceTemplatesError: FatalError {
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

protocol SynthesizedResourceInterfaceTemplatesLocating {
    func locateTemplate(for namespaceType: SynthesizedResourceInterfaceType) throws -> AbsolutePath
}

final class SynthesizedResourceInterfaceTemplatesLocator: SynthesizedResourceInterfaceTemplatesLocating {
    func locateTemplate(for synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType) throws -> AbsolutePath {
        let template = try locateResourcesNamespaceTemplatesDirectory().appending(component: synthesizedResourceInterfaceType.templateFileName)
        guard
            FileHandler.shared.exists(template)
        else {
            throw SynthesizedResourceInterfaceTemplatesError.fileNotFound(template)
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
            throw SynthesizedResourceInterfaceTemplatesError.fileNotFound(templatesPath)
        }
        return templatesPath
    }
}
