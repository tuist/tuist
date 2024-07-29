import Foundation
import Mockable
import Path
import TuistLoader
import TuistSupport

@Mockable
protocol ProjectViewServicing {
    func run(fullHandle: String?, path: String?) async throws
}

enum ProjectViewServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle: return "We couldn't view the project because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct ProjectViewService: ProjectViewServicing {
    private let opener: Opening
    private let configLoader: ConfigLoading

    init(
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.opener = opener
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, path _: String?) async throws {
        var fullHandle: String! = fullHandle
        var url: URL!

        if fullHandle != nil {
            url = Constants.URLs.production
        } else {
            let path = if let path {
                try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
            } else {
                FileHandler.shared.currentPath
            }
            let config = try await configLoader.loadConfig(path: path)
            url = config.url
            fullHandle = config.fullHandle
        }

        if fullHandle == nil {
            throw ProjectViewServiceError.missingFullHandle
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path = "/\(fullHandle!)"
        try opener.open(url: components.url!)
    }
}
