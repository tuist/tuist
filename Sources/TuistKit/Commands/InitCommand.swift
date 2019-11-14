import Basic
import Foundation
import SPMUtility
import TuistGenerator
import TuistSupport

private typealias Platform = TuistGenerator.Platform
private typealias Product = TuistGenerator.Product

enum InitCommandError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)

    var type: ErrorType {
        return .abort
    }

    var description: String {
        switch self {
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.pathString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.pathString)."
        }
    }

    static func == (lhs: InitCommandError, rhs: InitCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.ungettableProjectName(lhsPath), .ungettableProjectName(rhsPath)):
            return lhsPath == rhsPath
        case let (.nonEmptyDirectory(lhsPath), .nonEmptyDirectory(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

// swiftlint:disable:next type_body_length
class InitCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "init"
    static let overview = "Bootstraps a project."
    let platformArgument: OptionArgument<String>
    let pathArgument: OptionArgument<String>
    let nameArgument: OptionArgument<String>
    let playgroundGenerator: PlaygroundGenerating

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, playgroundGenerator: PlaygroundGenerator())
    }

    init(parser: ArgumentParser,
         playgroundGenerator: PlaygroundGenerating) {
        let subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
        platformArgument = subParser.add(option: "--platform",
                                         shortName: nil,
                                         kind: String.self,
                                         usage: "The platform (ios, tvos or macos) the product will be for (Default: ios).",
                                         completion: ShellCompletion.values([
                                             (value: "ios", description: "iOS platform"),
                                             (value: "tvos", description: "tvOS platform"),
                                             (value: "macos", description: "macOS platform"),
                                         ]))
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the project will be generated (Default: Current directory).",
                                     completion: .filename)
        nameArgument = subParser.add(option: "--name",
                                     shortName: "-n",
                                     kind: String.self,
                                     usage: "The name of the project. If it's not passed (Default: Name of the directory).",
                                     completion: nil)
        self.playgroundGenerator = playgroundGenerator
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let platform = try self.platform(arguments: arguments)
        let path = try self.path(arguments: arguments)
        let name = try self.name(arguments: arguments, path: path)
        try verifyDirectoryIsEmpty(path: path)
        try generateSetup(path: path)
        try generateProjectDescriptionHelpers(path: path)
        try generateProjectsDirectories(name: name, path: path)
        try generateProjectsSwift(name: name, platform: platform, path: path)
        try generateWorkspaceSwift(name: name, platform: platform, path: path)
        try generateSwiftFiles(name: name, platform: platform, path: path)
        try generatePlaygrounds(name: name, path: path, platform: platform)
        try generateTuistConfig(path: path)
        try generateGitIgnore(path: path)

        Printer.shared.print(success: "Project generated at path \(path.pathString).")
    }

    // MARK: - Fileprivate

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An InitCommandError.nonEmptyDirectory error when the directory is not empty.
    private func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw InitCommandError.nonEmptyDirectory(path)
        }
    }

    fileprivate func projectsPath(_ path: AbsolutePath) -> AbsolutePath {
        path.appending(component: "Projects")
    }

    fileprivate func appPath(_ path: AbsolutePath, name: String) -> AbsolutePath {
        return projectsPath(path).appending(component: name)
    }

    fileprivate func kitFrameworkPath(_ path: AbsolutePath, name: String) -> AbsolutePath {
        return projectsPath(path).appending(component: "\(name)Kit")
    }

    fileprivate func supportFrameworkPath(_ path: AbsolutePath, name: String) -> AbsolutePath {
        return projectsPath(path).appending(component: "\(name)Support")
    }

    private func generateProjectsDirectories(name: String, path: AbsolutePath) throws {
        func generate(for projectPath: AbsolutePath) throws {
            try FileHandler.shared.createFolder(projectPath)
            try FileHandler.shared.createFolder(projectPath.appending(component: "Sources"))
            try FileHandler.shared.createFolder(projectPath.appending(component: "Tests"))
            try FileHandler.shared.createFolder(projectPath.appending(component: "Playgrounds"))
        }
        try generate(for: appPath(path, name: name))
        try generate(for: kitFrameworkPath(path, name: name))
        try generate(for: supportFrameworkPath(path, name: name))
    }

    private func generateProjectDescriptionHelpers(path: AbsolutePath) throws {
        let helpersPath = path.appending(RelativePath("\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(helpersPath)

        let content = """
        import ProjectDescription

        extension Project {

            public static func app(name: String, platform: Platform, dependencies: [TargetDependency] = []) -> Project {
                return self.project(name: name, product: .app, platform: platform, dependencies: dependencies, infoPlist: [
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1"
                ])
            }

            public static func framework(name: String, platform: Platform, dependencies: [TargetDependency] = []) -> Project {
                return self.project(name: name, product: .framework, platform: platform, dependencies: dependencies)
            }
        
            public static func project(name: String,
                                       product: Product,
                                       platform: Platform,
                                       dependencies: [TargetDependency] = [],
                                       infoPlist: [String: InfoPlist.Value] = [:]) -> Project {
                return Project(name: name,
                               targets: [
                                Target(name: name,
                                        platform: platform,
                                        product: product,
                                        bundleId: "io.tuist.\\(name)",
                                        infoPlist: .extendingDefault(with: infoPlist),
                                        sources: ["Sources/**"],
                                        resources: [],
                                        dependencies: dependencies),
                                Target(name: "\\(name)Tests",
                                        platform: platform,
                                        product: .unitTests,
                                        bundleId: "io.tuist.\\(name)Tests",
                                        infoPlist: .default,
                                        sources: "Tests/**",
                                        dependencies: [
                                            .target(name: "\\(name)")
                                        ])
                              ])
            }

        }
        """
        let helperPath = helpersPath.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write(content, path: helperPath, atomically: true)
    }

    private func generateWorkspaceSwift(name: String, platform _: Platform, path: AbsolutePath) throws {
        let content = """
        import ProjectDescription
        import ProjectDescriptionHelpers
        
        let workspace = Workspace(name: "\(name)", projects: [
            "Projects/\(name)",
            "Projects/\(name)Kit",
            "Projects/\(name)Support"
        ])
        """
        try FileHandler.shared.write(content, path: path.appending(component: "Workspace.swift"), atomically: true)
    }

    private func generateProjectsSwift(name: String, platform: Platform, path: AbsolutePath) throws {
        let appContent = """
        import ProjectDescription
        import ProjectDescriptionHelpers
        
        let project = Project.app(name: "\(name)", platform: .\(platform.caseValue), dependencies: [
            .project(target: "\(name)Kit", path: .relativeToManifest("../\(name)Kit"))
        ])
        """
        let kitFrameworkContent = """
        import ProjectDescription
        import ProjectDescriptionHelpers
        
        let project = Project.framework(name: "\(name)Kit", platform: .\(platform.caseValue), dependencies: [
            .project(target: "\(name)Support", path: .relativeToManifest("../\(name)Support"))
        ])
        """
        let supportFrameworkContent = """
        import ProjectDescription
        import ProjectDescriptionHelpers
        
        let project = Project.framework(name: "\(name)Support", platform: .\(platform.caseValue), dependencies: [])
        """

        try FileHandler.shared.write(appContent, path: appPath(path, name: name).appending(component: "Project.swift"), atomically: true)
        try FileHandler.shared.write(kitFrameworkContent, path: kitFrameworkPath(path, name: name).appending(component: "Project.swift"), atomically: true)
        try FileHandler.shared.write(supportFrameworkContent, path: supportFrameworkPath(path, name: name).appending(component: "Project.swift"), atomically: true)
    }

    // swiftlint:disable:next function_body_length
    private func generateGitIgnore(path: AbsolutePath) throws {
        let path = path.appending(component: ".gitignore")
        let content = """
        ### macOS ###
        # General
        .DS_Store
        .AppleDouble
        .LSOverride

        # Icon must end with two \r
        Icon

        # Thumbnails
        ._*

        # Files that might appear in the root of a volume
        .DocumentRevisions-V100
        .fseventsd
        .Spotlight-V100
        .TemporaryItems
        .Trashes
        .VolumeIcon.icns
        .com.apple.timemachine.donotpresent

        # Directories potentially created on remote AFP share
        .AppleDB
        .AppleDesktop
        Network Trash Folder
        Temporary Items
        .apdisk

        ### Xcode ###
        # Xcode
        #
        # gitignore contributors: remember to update Global/Xcode.gitignore, Objective-C.gitignore & Swift.gitignore

        ## User settings
        xcuserdata/

        ## compatibility with Xcode 8 and earlier (ignoring not required starting Xcode 9)
        *.xcscmblueprint
        *.xccheckout

        ## compatibility with Xcode 3 and earlier (ignoring not required starting Xcode 4)
        build/
        DerivedData/
        *.moved-aside
        *.pbxuser
        !default.pbxuser
        *.mode1v3
        !default.mode1v3
        *.mode2v3
        !default.mode2v3
        *.perspectivev3
        !default.perspectivev3

        ### Xcode Patch ###
        *.xcodeproj/*
        !*.xcodeproj/project.pbxproj
        !*.xcodeproj/xcshareddata/
        !*.xcworkspace/contents.xcworkspacedata
        /*.gcno

        ### Projects ###
        *.xcodeproj
        *.xcworkspace

        ### Tuist derived files ###
        graph.dot
        """
        try content.write(to: path.url, atomically: true, encoding: .utf8)
    }

    /// Generates a Setup.swift file in the given directory.
    ///
    /// - Parameter path: Path where the Setup.swift file will be created.
    /// - Throws: An error if the file cannot be created.
    private func generateSetup(path: AbsolutePath) throws {
        let content = """
        import ProjectDescription

        let setup = Setup([
            // .homebrew(packages: ["swiftlint", "carthage"]),
            // .carthage()
        ])
        """
        let setupPath = path.appending(component: Manifest.setup.fileName)
        try content.write(to: setupPath.url, atomically: true, encoding: .utf8)
    }

    private func generateTuistConfig(path: AbsolutePath) throws {
        let content = """
        import ProjectDescription

        let config = TuistConfig(generationOptions: [
            .generateManifest
        ])
        """
        let setupPath = path.appending(component: Manifest.tuistConfig.fileName)
        try content.write(to: setupPath.url, atomically: true, encoding: .utf8)
    }

    // swiftlint:disable:next function_body_length
    private func generateSwiftFiles(name: String, platform: Platform, path: AbsolutePath) throws {
        let appContent: String!
        if platform == .macOS {
            appContent = """
            import Cocoa
            import \(name)Kit
            
            @NSApplicationMain
            class AppDelegate: NSObject, NSApplicationDelegate {
            
                @IBOutlet weak var window: NSWindow!
            
                func applicationDidFinishLaunching(_ aNotification: Notification) {
                    // Insert code here to initialize your application
                }
            
                func applicationWillTerminate(_ aNotification: Notification) {
                    // Insert code here to tear down your application
                }
            
            }
            """
        } else {
            appContent = """
            import UIKit
            import \(name)Kit
            
            @UIApplicationMain
            class AppDelegate: UIResponder, UIApplicationDelegate {
            
                var window: UIWindow?
            
                func application(
                    _ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
                ) -> Bool {
                    window = UIWindow(frame: UIScreen.main.bounds)
                    let viewController = UIViewController()
                    viewController.view.backgroundColor = .white
                    window?.rootViewController = viewController
                    window?.makeKeyAndVisible()
                    return true
                }
            
            }
            """
        }
        let kitSourceContent = """
        import Foundation
        import \(name)Support
        
        public final class \(name) {}
        """
        let supportSourceContent = """
        import Foundation
        
        public final class \(name) {}
        """

        func testsContent(_ name: String) -> String {
            return """
            import Foundation
            import XCTest
            
            @testable import \(name)

            final class \(name)Tests: XCTestCase {
            
            }
            """
        }

        // App
        let appSourcesPath = appPath(path, name: name).appending(RelativePath("Sources"))
        let appTestsPath = appPath(path, name: name).appending(RelativePath("Tests"))
        try FileHandler.shared.write(appContent, path: appSourcesPath.appending(component: "AppDelegate.swift"), atomically: true)
        try FileHandler.shared.write(testsContent(name), path: appTestsPath.appending(component: "\(name)Tests.swift"), atomically: true)

        // Kit
        let kitSourcesPath = kitFrameworkPath(path, name: name).appending(RelativePath("Sources"))
        let kitTestsPath = kitFrameworkPath(path, name: name).appending(RelativePath("Tests"))
        try FileHandler.shared.write(kitSourceContent, path: kitSourcesPath.appending(component: "\(name)Kit.swift"), atomically: true)
        try FileHandler.shared.write(testsContent("\(name)Kit"), path: kitTestsPath.appending(component: "\(name)KitTests.swift"), atomically: true)

        // Support
        let supportSourcesPath = supportFrameworkPath(path, name: name).appending(RelativePath("Sources"))
        let supportTestsPath = supportFrameworkPath(path, name: name).appending(RelativePath("Tests"))
        try FileHandler.shared.write(supportSourceContent, path: supportSourcesPath.appending(component: "\(name)Support.swift"), atomically: true)
        try FileHandler.shared.write(testsContent("\(name)Support"), path: supportTestsPath.appending(component: "\(name)SupportTests.swift"), atomically: true)
    }

    private func generatePlaygrounds(name: String, path: AbsolutePath, platform: Platform) throws {
        try playgroundGenerator.generate(path: kitFrameworkPath(path, name: name).appending(component: "Playgrounds"),
                                         name: "\(name)Kit",
                                         platform: platform,
                                         content: PlaygroundGenerator.defaultContent())
        try playgroundGenerator.generate(path: supportFrameworkPath(path, name: name).appending(component: "Playgrounds"),
                                         name: "\(name)Support",
                                         platform: platform,
                                         content: PlaygroundGenerator.defaultContent())
    }

    private func name(arguments: ArgumentParser.Result, path: AbsolutePath) throws -> String {
        if let name = arguments.get(nameArgument) {
            return name
        } else if let name = path.components.last {
            return name
        } else {
            throw InitCommandError.ungettableProjectName(AbsolutePath.current)
        }
    }

    private func path(arguments: ArgumentParser.Result) throws -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func platform(arguments: ArgumentParser.Result) throws -> Platform {
        if let platformString = arguments.get(self.platformArgument) {
            if let platform = Platform(rawValue: platformString) {
                return platform
            } else {
                throw ArgumentParserError.invalidValue(argument: "platform", error: .custom("Platform should be either ios, tvos, or macos"))
            }
        } else {
            return .iOS
        }
    }
}
