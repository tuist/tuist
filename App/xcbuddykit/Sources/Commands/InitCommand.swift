import Basic
import Foundation
import Utility

struct ProjectSwiftModel {
    var path: AbsolutePath
    var name: String
    var platform: Platform
}

/// Init command error
///
/// - alreadyExists: when a file already exists.
enum InitCommandError: FatalError {
    case alreadyExists(AbsolutePath)
    case ungettableProjectName(AbsolutePath)
    case invalidPlatform(String)

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
        case let .invalidPlatform(platform):
            return "\(platform) is not a valid platform. Available platforms: ios|macos|watchos|tvos"
        }
    }
}

/// Command that initializes a Project.swift in the current folder.
public class InitCommand: NSObject, Command {
    
    enum WizardQuestion {
        static let name = "1. What's the name of your project? (Leave empty to use the name of the project folder: %@)"
        static let path = "2. Where would you like to generate the Project.swift file? (Leave empty to use current directory)"
        static let platform = "3. Which platform is your project (ios|macos|watchos|tvos)? (Leave empty to use ios plaftform)"
        static let generate = "Would you want generate xcodeproj now?"
    }

    // MARK: - Command

    /// Command name.
    public static let command = "init"

    /// Command description.
    public static let overview = "Initializes a Project.swift in the current folder."

    /// Path argument.
    let pathArgument: OptionArgument<String>
    
    /// Name argument.
    let nameArgument: OptionArgument<String>
    
    /// Generate argument.
    let generateArgument: OptionArgument<Bool>
    
    /// Interactive argument.
    let interactiveArgument: OptionArgument<Bool>
    
    /// Platform argument.
    let platformArgument: OptionArgument<String>
    
    /// Type argument.
    let typeArgument: OptionArgument<String>

    /// Context
    let context: CommandsContexting

    public required init(parser: ArgumentParser) {
        let subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the Project.swift file will be generated",
                                     completion: .filename)
        
        nameArgument = subParser.add(option: "--name",
                                     shortName: "-n",
                                     kind: String.self,
                                     usage: "The name of the Project will be generated",
                                     completion: .none)
        
        generateArgument = subParser.add(option: "--generate",
                                     shortName: "-g",
                                     kind: Bool.self,
                                     usage: "Generate xcodeproj after create Project.swift file",
                                     completion: .none)
        
        interactiveArgument = subParser.add(option: "--interactive",
                                         shortName: "-i",
                                         kind: Bool.self,
                                         usage: "Launch wizard to request project details",
                                         completion: .none)
        
        platformArgument = subParser.add(option: "--platform",
                                     shortName: "-pf",
                                     kind: String.self,
                                     usage: "The platform of the Project will be generated",
                                     completion: ShellCompletion.values([(value: "ios", description: ""),
                                                                         (value: "macos", description: ""),
                                                                         (value: "watchos", description: ""),
                                                                         (value: "tvos", description: "")]))
        
        typeArgument = subParser.add(option: "--type",
                                     shortName: "-t",
                                     kind: String.self,
                                     usage: "The type of the Project will be generated",
                                     completion: .none)

        context = CommandsContext()
    }

    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with arguments: ArgumentParser.Result) throws {
        let isInteractiveModeActive = parseInteractive(with: arguments)
        let projectSwiftData = try parseProjectFileData(with: arguments, interactive: isInteractiveModeActive)
        
        if context.fileHandler.exists(projectSwiftData.path) {
            throw InitCommandError.alreadyExists(projectSwiftData.path)
        }
        
        let projectSwift = self.projectSwift(name: projectSwiftData.name, platform: projectSwiftData.platform)
        try projectSwift.write(toFile: projectSwiftData.path.asString,
                               atomically: true,
                               encoding: .utf8)
        context.printer.print(section: "🎉 Project.swift generated at path \(projectSwiftData.path.asString)")

        if checkIfNeedGenerateProject(with: arguments, interactive: isInteractiveModeActive) {
            // TODO: Generate xcodeproj
        }
    }
    
    /// Parses the arguments and check if user wants to use the interactive mode.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: is interactive mode is active or not
    private func parseInteractive(with arguments: ArgumentParser.Result) -> Bool {
        return arguments.get(interactiveArgument) != nil ? true : false
    }
    
    /// Parses the arguments and check if user wants to generate the xcodeproj after create
    /// the Projet.swift file
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: need generate xcodeproj
    private func parseGenerate(with arguments: ArgumentParser.Result) -> Bool {
        return arguments.get(generateArgument) != nil ? true : false
    }
    
    /// Parses the arguments and returns the path to the folder where the manifest file is.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the path to the folder where the manifest is.
    private func parsePath(with arguments: ArgumentParser.Result) -> AbsolutePath {
        var path: AbsolutePath! = arguments
            .get(pathArgument)
            .map({ AbsolutePath($0) })
            .map({ $0.appending(component: Constants.Manifest.project) })
        if path == nil {
            path = AbsolutePath.current.appending(component: Constants.Manifest.project)
        }
        return path
    }
    
    /// Parses the arguments and returns the project name.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the path to the folder where the manifest is.
    private func parseProjectName(with arguments: ArgumentParser.Result, path: AbsolutePath) throws -> String {
        if let name = arguments.get(nameArgument) ?? path.parentDirectory.components.last {
            return name
        } else {
            throw InitCommandError.ungettableProjectName(path)
        }
    }
    
    /// Parses the arguments and returns the project platform.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the project platform.
    private func parsePlatform(with arguments: ArgumentParser.Result) throws -> Platform {
        guard let platform = arguments.get(platformArgument) else { return .ios }
        if let platformType = Platform(rawValue: platform) {
            return platformType
        } else {
            throw InitCommandError.invalidPlatform(platform)
        }
    }
    
    /// Parses the arguments and returns a ProjectSwiftModel with project data.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Parameter interactive: flag to active interactive mode
    /// - Returns: model with all project data.
    private func parseProjectFileData(with arguments: ArgumentParser.Result, interactive: Bool = false) throws -> ProjectSwiftModel {
        if interactive {
            return try startWizard()
        }
        let path = parsePath(with: arguments)
        let projectName = try parseProjectName(with: arguments, path: path)
        let platform = try parsePlatform(with: arguments)
        return ProjectSwiftModel(path: path,
                                 name: projectName,
                                 platform: platform)
    }
    
    /// Check if user wants generate xcodeproj after create Project.swift file.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Parameter interactive: flag to active interactive mode
    /// - Returns: need generate xcodeproj or not
    private func checkIfNeedGenerateProject(with arguments: ArgumentParser.Result, interactive: Bool = false) -> Bool {
        if !interactive {
            return parseGenerate(with: arguments)
        }
        return context.userInputRequester.bool(message: WizardQuestion.generate)
    }
    
    /// Start wizard to retrive info needed to create the Project.swift file
    ///
    /// - Returns: model with all project data.
    private func startWizard() throws -> ProjectSwiftModel {
        let path = askForPath()
        let projectName = askForProjectName()
        let platform = try askForPlatform()
        return ProjectSwiftModel(path: path,
                                name: projectName,
                                platform: platform)
    }
    
    /// Ask user what is the project name
    ///
    /// - Returns: project name
    private func askForProjectName() -> String {
        let folderName = AbsolutePath.current.components.last!
        let projectName = context.userInputRequester.optional(message: String(format: WizardQuestion.name, folderName))
        return projectName ?? folderName
    }
    
    /// Ask user the path to the folder where the manifest file is
    ///
    /// - Returns: manifest file path
    private func askForPath() -> AbsolutePath {
        var path = AbsolutePath.current
        if let userInputPath = context.userInputRequester.optional(message: WizardQuestion.path) {
            path = AbsolutePath(userInputPath)
        }
        return path.appending(component: Constants.Manifest.project)
    }
    
    /// Ask user which platform the project is
    ///
    /// - Returns: project platform
    private func askForPlatform() throws -> Platform {
        guard let platform = context.userInputRequester.optional(message: WizardQuestion.platform) else { return .ios }
        if let platformType = Platform(rawValue: platform) {
            return platformType
        } else {
            throw InitCommandError.invalidPlatform(platform)
        }
    }

    fileprivate func projectSwift(name: String, platform: Platform) -> String {
        return """
        import ProjectDescription
        
         let project = Project(name: "{{NAME}}",
                      schemes: [
                          /* Project schemes are defined here */
                          Scheme(name: "{{NAME}}",
                                 shared: true,
                                 buildAction: BuildAction(targets: ["{{NAME}}"])),
                      ],
                      settings: Settings(base: [:]),
                      targets: [
                          Target(name: "{{NAME}}",
                                 platform: .{{PLATFORM}},
                                 product: .app,
                                 bundleId: "io.xcbuddy.{{NAME}}",
                                 infoPlist: "Info.plist",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "framework") */
                                 ],
                                 settings: nil,
                                 buildPhases: [
                                    
                                     .sources([.sources("./Sources/**/*.swift")]),
                                     /* Other build phases can be added here */
                                     /* .resources([.include(["./Resousrces /**/ *"])]) */
                                ]),
                    ])
        """.replacingOccurrences(of: "{{NAME}}", with: name)
           .replacingOccurrences(of: "{{PLATFORM}}", with: platform.rawValue)
    }
}
