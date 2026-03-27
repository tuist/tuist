import FileSystem
import TuistCore
import TuistGit
import TuistSupport

public protocol TemplateGitLoading {
    /// Load `TuistCore.Template` from the given Git repository
    /// to a temporary directory and performs `closure` on that template.
    /// - Parameters:
    ///     - templateURL: Git repository url
    ///     - closure: Closure to perform work on loaded template
    func loadTemplate(from templateURL: String, closure: @escaping (TuistCore.Template) async throws -> Void) async throws
}

public struct TemplateGitLoader: TemplateGitLoading {
    private let templateLoader: TemplateLoading
    private let fileSystem: FileSysteming
    private let gitController: GitControlling
    private let templateLocationParser: TemplateLocationParsing

    /// Default constructor.
    public init() {
        self.init(
            templateLoader: TemplateLoader(),
            fileSystem: FileSystem(),
            gitController: GitController(),
            templateLocationParser: TemplateLocationParser()
        )
    }

    init(
        templateLoader: TemplateLoading,
        fileSystem: FileSysteming,
        gitController: GitControlling,
        templateLocationParser: TemplateLocationParsing
    ) {
        self.templateLoader = templateLoader
        self.fileSystem = fileSystem
        self.gitController = gitController
        self.templateLocationParser = templateLocationParser
    }

    public func loadTemplate(
        from templateURL: String,
        closure: @escaping (TuistCore.Template) async throws -> Void
    ) async throws {
        let repoURL = templateLocationParser.parseRepositoryURL(from: templateURL)
        let repoBranch = templateLocationParser.parseRepositoryBranch(from: templateURL)

        try await fileSystem.runInTemporaryDirectory(prefix: "TemplateGit") { temporaryPath in
            let templatePath = temporaryPath.appending(component: "Template")
            try await fileSystem.makeDirectory(at: templatePath)
            try gitController.clone(url: repoURL, to: templatePath)
            if let repoBranch {
                try gitController.checkout(id: repoBranch, in: templatePath)
            }
            let template = try await templateLoader.loadTemplate(at: templatePath, plugins: .none)
            try await closure(template)
        }
    }
}

#if DEBUG
    public final class MockTemplateGitLoader: TemplateGitLoading {
        public init() {}

        public var loadTemplateStub: ((String) throws -> Template)?
        public func loadTemplate(from templateURL: String, closure: @escaping (Template) async throws -> Void) async throws {
            let template = try loadTemplateStub?(templateURL) ?? Template(description: "", attributes: [], items: [])
            try await closure(template)
        }
    }
#endif
