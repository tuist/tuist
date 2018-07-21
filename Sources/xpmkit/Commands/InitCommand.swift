import Basic
import Foundation
import Utility
import xpmcore

enum InitCommandError: FatalError {
    case alreadyExists(AbsolutePath)
    case ungettableProjectName(AbsolutePath)

    var type: ErrorType {
        return .abort
    }

    var description: String {
        switch self {
        case let .alreadyExists(path):
            return "\(path.asString) already exists."
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.asString)."
        }
    }
}

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

    // MARK: - Init

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
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the project will be generated.",
                                     completion: .filename)
        nameArgument = subParser.add(option: "--name",
                                     shortName: "-n",
                                     kind: String.self,
                                     usage: "The name of the project. If it's not passed, the name of the folder will be used.",
                                     completion: nil)
        self.fileHandler = fileHandler
        self.printer = printer
        self.infoplistProvisioner = infoplistProvisioner
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let product = try self.product(arguments: arguments)
        let platform = try self.platform(arguments: arguments)
        let path = try self.path(arguments: arguments)
        let name = try self.name(arguments: arguments, path: path)
        try generateProjectSwift(name: name, platform: platform, product: product, path: path)
        try generateSources(name: name, platform: platform, product: product, path: path)
        try generateTests(name: name, path: path)
        try generatePlists(platform: platform, product: product, path: path)
        printer.print(success: "Project generated at path \(path.asString).")
    }

    // MARK: - Fileprivate

    fileprivate func generateProjectSwift(name: String, platform: Platform, product: Product, path: AbsolutePath) throws {
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

    fileprivate func generateSources(name: String, platform: Platform, product: Product, path: AbsolutePath) throws {
        let path = path.appending(component: "Sources")

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

    fileprivate func generateTests(name: String, path: AbsolutePath) throws {
        let path = path.appending(component: "Tests")

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
