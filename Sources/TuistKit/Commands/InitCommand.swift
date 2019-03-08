import Basic
import Foundation
import TuistCore
import Utility

enum InitCommandError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)

    var type: ErrorType {
        return .abort
    }

    var description: String {
        switch self {
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.asString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.asString)."
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
    let productArgument: OptionArgument<String>
    let pathArgument: OptionArgument<String>
    let nameArgument: OptionArgument<String>
    let fileHandler: FileHandling
    let printer: Printing
    let infoplistProvisioner: InfoPlistProvisioning
    let playgroundGenerator: PlaygroundGenerating

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  infoplistProvisioner: InfoPlistProvisioner(),
                  playgroundGenerator: PlaygroundGenerator())
    }

    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         infoplistProvisioner: InfoPlistProvisioning,
         playgroundGenerator: PlaygroundGenerating) {
        let subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
        productArgument = subParser.add(option: "--product",
                                        shortName: nil,
                                        kind: String.self,
                                        usage: "The product (application or framework) the generated project will build (Default: application).",
                                        completion: ShellCompletion.values([
                                            (value: "application", description: "Application"),
                                            (value: "framework", description: "Framework"),
        ]))
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
        self.fileHandler = fileHandler
        self.printer = printer
        self.infoplistProvisioner = infoplistProvisioner
        self.playgroundGenerator = playgroundGenerator
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let product = try self.product(arguments: arguments)
        let platform = try self.platform(arguments: arguments)
        let path = try self.path(arguments: arguments)
        let name = try self.name(arguments: arguments, path: path)
        try verifyDirectoryIsEmpty(path: path)
        try generateProjectSwift(name: name, platform: platform, product: product, path: path)
        try generateSources(name: name, platform: platform, product: product, path: path)
        try generateTests(name: name, path: path)
        try generatePlists(platform: platform, product: product, path: path)
        try generatePlaygrounds(name: name, path: path, platform: platform)
        try generateGitIgnore(path: path)
        printer.print(success: "Project generated at path \(path.asString).")
    }

    // MARK: - Fileprivate

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An InitCommandError.nonEmptyDirectory error when the directory is not empty.
    fileprivate func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw InitCommandError.nonEmptyDirectory(path)
        }
    }

    fileprivate func generateProjectSwift(name: String, platform: Platform, product: Product, path: AbsolutePath) throws {
        let content = """
        import ProjectDescription
        
        let project = Project(name: "\(name)",
                              targets: [
                                Target(name: "\(name)",
                                       platform: .\(platform.caseValue),
                                       product: .\(product.caseValue),
                                       bundleId: "io.tuist.\(name)",
                                       infoPlist: "Info.plist",
                                       sources: ["Sources/**"],
                                       resources: ["Resources/**"],
                                       dependencies: [
                                            /* Target dependencies can be defined here */
                                            /* .framework(path: "framework") */
                                        ]),
                                Target(name: "\(name)Tests",
                                       platform: .\(platform.caseValue),
                                       product: .unitTests,
                                       bundleId: "io.tuist.\(name)Tests",
                                       infoPlist: "Tests.plist",
                                       sources: "Tests/**",
                                       dependencies: [
                                            .target(name: "\(name)")
                                       ])
                              ])
        """
        try content.write(to: path.appending(component: "Project.swift").url, atomically: true, encoding: .utf8)
    }

    fileprivate func generatePlists(platform: Platform, product: Product, path: AbsolutePath) throws {
        try infoplistProvisioner.generate(path: path.appending(component: "Info.plist"),
                                          platform: platform,
                                          product: product)
        try infoplistProvisioner.generate(path: path.appending(component: "Tests.plist"),
                                          platform: platform,
                                          product: .unitTests)
    }

    // swiftlint:disable:next function_body_length
    fileprivate func generateGitIgnore(path: AbsolutePath) throws {
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
        """
        try content.write(to: path.url, atomically: true, encoding: .utf8)
    }

    // swiftlint:disable:next function_body_length
    fileprivate func generateSources(name: String, platform: Platform, product: Product, path: AbsolutePath) throws {
        let path = path.appending(component: "Sources")

        try fileHandler.createFolder(path)

        var content: String!
        var filename: String!

        if platform == .macOS, product == .app {
            filename = "AppDelegate.swift"
            content = """
            import Cocoa
            
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
        } else if [.iOS, .tvOS].contains(platform), product == .app {
            filename = "AppDelegate.swift"

            content = """
            import UIKit
            
            @UIApplicationMain
            class AppDelegate: UIResponder, UIApplicationDelegate {
            
                var window: UIWindow?
            
                func application(_ application: UIApplication,
                                   didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
                    window = UIWindow(frame: UIScreen.main.bounds)
                    let viewController = UIViewController()
                    viewController.view.backgroundColor = .white
                    window?.rootViewController = viewController
                    window?.makeKeyAndVisible()
                    return true
                }
            
            }
            """
        } else {
            filename = "\(name).swift"
            content = """
            import Foundation
            
            class \(name) {
            
            }
            """
        }

        try content.write(to: path.appending(component: filename).url, atomically: true, encoding: .utf8)
    }

    fileprivate func generateTests(name: String, path: AbsolutePath) throws {
        let path = path.appending(component: "Tests")

        try fileHandler.createFolder(path)

        let content = """
        import Foundation
        import XCTest
        
        @testable import \(name)

        final class \(name)Tests: XCTestCase {
        
        }
        """
        try content.write(to: path.appending(component: "\(name)Tests.swift").url, atomically: true, encoding: .utf8)
    }

    fileprivate func generatePlaygrounds(name: String, path: AbsolutePath, platform: Platform) throws {
        let playgroundsPath = path.appending(component: "Playgrounds")
        try fileHandler.createFolder(playgroundsPath)
        try playgroundGenerator.generate(path: playgroundsPath,
                                         name: name,
                                         platform: platform,
                                         content: PlaygroundGenerator.defaultContent())
    }

    fileprivate func name(arguments: ArgumentParser.Result, path: AbsolutePath) throws -> String {
        if let name = arguments.get(nameArgument) {
            return name
        } else if let name = path.components.last {
            return name
        } else {
            throw InitCommandError.ungettableProjectName(AbsolutePath.current)
        }
    }

    fileprivate func path(arguments: ArgumentParser.Result) throws -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: fileHandler.currentPath)
        } else {
            return fileHandler.currentPath
        }
    }

    fileprivate func product(arguments: ArgumentParser.Result) throws -> Product {
        if let productString = arguments.get(self.productArgument) {
            let valid = ["application", "framework"]
            if valid.contains(productString) {
                return (productString == "application") ? .app : .framework
            } else {
                throw ArgumentParserError.invalidValue(argument: "product", error: .custom("Product should be either app or framework"))
            }
        } else {
            return .app
        }
    }

    fileprivate func platform(arguments: ArgumentParser.Result) throws -> Platform {
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
