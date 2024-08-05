import TuistCore
import TuistSupport

public protocol TemplateGitLoading {
    /// Load `TuistCore.Template` from the given Git repository
    /// to a temporary directory and performs `closure` on that template.
    /// - Parameters:
    ///     - templateURL: Git repository url
    ///     - closure: Closure to perform work on loaded template
    func loadTemplate(from templateURL: String, closure: @escaping (TuistCore.Template) async throws -> Void) async throws
}

public final class TemplateGitLoader: TemplateGitLoading {
    private let templateLoader: TemplateLoading
    private let fileHandler: FileHandling
    private let gitHandler: GitHandling
    private let templateLocationParser: TemplateLocationParsing

    /// Default constructor.
    public convenience init() {
        self.init(
            templateLoader: TemplateLoader(),
            fileHandler: FileHandler.shared,
            gitHandler: GitHandler(),
            templateLocationParser: TemplateLocationParser()
        )
    }

    init(
        templateLoader: TemplateLoading,
        fileHandler: FileHandling,
        gitHandler: GitHandling,
        templateLocationParser: TemplateLocationParsing
    ) {
        self.templateLoader = templateLoader
        self.fileHandler = fileHandler
        self.gitHandler = gitHandler
        self.templateLocationParser = templateLocationParser
    }

    public func loadTemplate(
        from templateURL: String,
        closure: @escaping (TuistCore.Template) async throws -> Void
    ) async throws {
        let repoURL = templateLocationParser.parseRepositoryURL(from: templateURL)
        let repoBranch = templateLocationParser.parseRepositoryBranch(from: templateURL)

        try await fileHandler.inTemporaryDirectory { temporaryPath in
            let templatePath = temporaryPath.appending(component: "Template")
            try self.fileHandler.createFolder(templatePath)
            try self.gitHandler.clone(url: repoURL, to: templatePath)
            if let repoBranch {
                try self.gitHandler.checkout(id: repoBranch, in: templatePath)
            }
            let template = try await self.templateLoader.loadTemplate(at: templatePath, plugins: .none)
            try await closure(template)
        }
    }
}
