import Basic
import Foundation
import Utility
import xpmcore

/// Init command error
///
/// - alreadyExists: when a file already exists.
enum InitCommandError: FatalError {
    case alreadyExists(AbsolutePath)
    case ungettableProjectName(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        return .abort
    }

    /// Error description.
    var description: String {
        switch self {
        case let .alreadyExists(path):
            return "\(path.asString) already exists"
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.asString)"
        }
    }
}

/// Command that initializes a Project.swift in the current folder.
public class InitCommand: NSObject, Command {

    // MARK: - Command

    /// Command name.
    public static let command = "init"

    /// Command description.
    public static let overview = "Bootstraps a project in the current directory."

    /// Platform argument.
    let platformArgument: OptionArgument<String>

    /// Product argument.
    let productArgument: OptionArgument<String>

    /// File handler.
    let fileHandler: FileHandling

    /// Printer.
    let printer: Printing

    /// Info.plist provisioner
    let infoplistProvisioner: InfoPlistProvisioning

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  infoplistProvisioner: InfoPlistProvisioner())
    }

    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         infoplistProvisioner: InfoPlistProvisioning) {
        let subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
        productArgument = subParser.add(option: "--product",
                                        shortName: nil,
                                        kind: String.self,
                                        usage: "The product (application or framework) the generated project will build.",
                                        completion: ShellCompletion.values([
                                            (value: "application", description: "Application"),
                                            (value: "framework", description: "Framework"),
        ]))
        platformArgument = subParser.add(option: "--platform",
                                         shortName: nil,
                                         kind: String.self,
                                         usage: "The platform (ios or macos) the product will be for.",
                                         completion: ShellCompletion.values([
                                             (value: "ios", description: "iOS platform"),
                                             (value: "macos", description: "macOS platform"),
        ]))
        self.fileHandler = fileHandler
        self.printer = printer
        self.infoplistProvisioner = infoplistProvisioner
    }

    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with arguments: ArgumentParser.Result) throws {
        let product = try self.product(arguments: arguments)
        let platform = try self.platform(arguments: arguments)
        let name = try self.name()
        try generateProjectSwift(name: name, platform: platform, product: product)
        try generateSources(name: name, platform: platform, product: product)
        try generateTests(name: name)
        try generatePlists(platform: platform, product: product)
    }

    fileprivate func generateProjectSwift(name: String, platform: Platform, product: Product) throws {
        let content = """
        import ProjectDescription
        
         let project = Project(name: "\(name)",
                      schemes: [
                          /* Project schemes are defined here */
                      ],
                      settings: Settings(base: [:]),
                      targets: [
                          Target(name: "\(name)",
                                 platform: .\(platform.rawValue),
                                 product: .\(product.rawValue),
                                 bundleId: "com.xcodepm.\(name)",
                                 infoPlist: "Info.plist",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "framework") */
                                 ],
                                 settings: nil,
                                 buildPhases: [
                                     .sources([.sources("./Sources/**/*.swift")]),
                                     /* Other build phases can be added here */
                                     /* .resources([.include(["./Resources/**/*"])]) */
                                ]),
                          Target(name: "\(name)Tests",
                                 platform: .\(platform.rawValue),
                                 product: .unitTests,
                                 bundleId: "com.xcodepm.\(name)Tests",
                                 infoPlist: "Tests.plist",
                                 dependencies: [
                                   .target(name: "\(name)")
                                 ],
                                 settings: nil,
                                 buildPhases: [
                                     .sources([.sources("./Tests/**/*.swift")]),
                                ]),
        
                        
                    ])
        """
        try content.write(to: fileHandler.currentPath.appending(component: "Project.swift").url, atomically: true, encoding: .utf8)
    }

    fileprivate func generatePlists(platform: Platform, product: Product) throws {
        try infoplistProvisioner.generate(path: fileHandler.currentPath.appending(component: "Info.plist"),
                                          platform: platform,
                                          product: product)
        try infoplistProvisioner.generate(path: fileHandler.currentPath.appending(component: "Tests.plist"),
                                          platform: platform,
                                          product: .unitTests)
    }

    fileprivate func generateSources(name: String, platform: Platform, product: Product) throws {
        let path = fileHandler.currentPath.appending(component: "Sources")

        if fileHandler.exists(path) {
            throw InitCommandError.alreadyExists(path)
        }
        try fileHandler.createFolder(path)

        var content: String!
        var filename: String!

        if platform == .macOS && product == .app {
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
        } else if platform == .iOS && product == .app {
            filename = "AppDelegate.swift"

            content = """
            import UIKit
            
            @UIApplicationMain
            class AppDelegate: UIResponder, UIApplicationDelegate {
            
                var window: UIWindow?
            
                func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
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

    /// Generates the tests folder with a base tests file.
    ///
    /// - Parameter name: project name.
    /// - Throws: an error if the tests folder cannot be created.
    fileprivate func generateTests(name: String) throws {
        let path = fileHandler.currentPath.appending(component: "Tests")

        if fileHandler.exists(path) {
            throw InitCommandError.alreadyExists(path)
        }
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

    /// Returns the name that should be used for the project.
    ///
    /// - Returns: project name.
    /// - Throws: an error if the name cannot be obtained.
    fileprivate func name() throws -> String {
        if let name = fileHandler.currentPath.components.last {
            return name
        } else {
            throw InitCommandError.ungettableProjectName(AbsolutePath.current)
        }
    }

    /// Returns the product by parsing the arguments.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the product that should be used for the project.
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

    /// Returns the platform by parsing the arguments.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the platform that should be used for the project.
    fileprivate func platform(arguments: ArgumentParser.Result) throws -> Platform {
        if let platformString = arguments.get(self.platformArgument) {
            let valid = ["ios", "macos"]
            if valid.contains(platformString) {
                return (platformString == "ios") ? .iOS : .macOS
            } else {
                throw ArgumentParserError.invalidValue(argument: "platform", error: .custom("Platform should be either ios or macos"))
            }
        } else {
            return .iOS
        }
    }
}
