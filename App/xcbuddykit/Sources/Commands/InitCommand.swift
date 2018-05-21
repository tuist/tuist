import Basic
import Foundation
import Utility

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
            return "⚠️  \(path.asString) already exists"
        case let .ungettableProjectName(path):
            return "❌  Couldn't infer the project name from path \(path.asString)"
        }
    }
}

/// Command that initializes a Project.swift in the current folder.
public class InitCommand: NSObject, Command {

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
                                     shortName: "-f",
                                     kind: Bool.self,
                                     usage: "Force generation of xcodeproj",
                                     completion: .none)
        context = CommandsContext()
    }

    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with arguments: ArgumentParser.Result) throws {
        let path = try parsePath(with: arguments)
        let projectName = try parseProjectName(with: arguments, path: path)
        let projectSwift = self.projectSwift(name: projectName)
        try projectSwift.write(toFile: path.asString,
                               atomically: true,
                               encoding: .utf8)
        context.printer.print(section: "🎉 Project.swift generated at path \(path.asString)")
//        _ = context.inputRequerer.requestBoolUserInput(message: "Do you want to generate xcodeproj?")
    }
    
    /// Parses the arguments and returns the path to the folder where the manifest file is.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the path to the folder where the manifest is.
    private func parsePath(with arguments: ArgumentParser.Result) throws -> AbsolutePath {
        var path: AbsolutePath! = arguments
            .get(pathArgument)
            .map({ AbsolutePath($0) })
            .map({ $0.appending(component: Constants.Manifest.project) })
        if path == nil {
            path = AbsolutePath.current.appending(component: Constants.Manifest.project)
        }
        if context.fileHandler.exists(path) {
            throw InitCommandError.alreadyExists(path)
        }
        return path
    }
    
    /// Parses the arguments and returns the project name.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the path to the folder where the manifest is.
    private func parseProjectName(with arguments: ArgumentParser.Result, path: AbsolutePath) throws -> String {
        var name = arguments.get(nameArgument)
        if name == nil {
            name = path.parentDirectory.components.last
        }
        if let finalName = name {
            return finalName
        } else {
            throw InitCommandError.ungettableProjectName(path)
        }
    }

    fileprivate func projectSwift(name: String) -> String {
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
                                 platform: .ios,
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
    }
}
