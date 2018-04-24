import Basic
import Foundation
import Utility

/// Init command error
///
/// - alreadyExists: when a file already exists.
enum InitCommandError: Error, CustomStringConvertible {
    case alreadyExists(AbsolutePath)
    case ungettableProjectName(AbsolutePath)
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
    public let command = "init"

    /// Command description.
    public let overview = "Initializes a Project.swift in the current folder."

    /// Path argument.
    let pathArgument: OptionArgument<String>

    /// Printer
    let printer: Printing

    private let fileHandler: FileHandling

    public required init(parser: ArgumentParser) {
        let subParser = parser.add(subparser: command, overview: overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the Project.swift file will be generated",
                                     completion: .filename)
        fileHandler = FileHandler()
        printer = Printer()
    }

    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with arguments: ArgumentParser.Result) throws {
        var path: AbsolutePath! = arguments
            .get(pathArgument)
            .map({ AbsolutePath($0) })
            .map({ $0.appending(component: Constants.Manifest.project) })
        if path == nil {
            path = AbsolutePath.current.appending(component: Constants.Manifest.project)
        }
        if fileHandler.exists(path) {
            throw InitCommandError.alreadyExists(path)
        }
        guard let projectName = path.parentDirectory.components.last else {
            throw InitCommandError.ungettableProjectName(path)
        }
        let projectSwift = self.projectSwift(name: projectName)
        try projectSwift.write(toFile: path.asString,
                               atomically: true,
                               encoding: .utf8)
        printer.print(section: "Project.swift generated at path \(path.asString)")
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
                      settings: Settings(base: [:],
                                         debug: Configuration(settings: [:],
                                                              xcconfig: "Debug.xcconfig")),
                      targets: [
                          Target(name: "{{NAME}}",
                                 platform: .ios,
                                 product: .app,
                                 bundleId: "com.xcbuddy.{{NAME}}",
                                 infoPlist: "Info.plist",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "/path/framework.framework") */
                                 ],
                                 settings: nil,
                                 buildPhases: [
                                     .sources([.include(["./Sources/**/*.swift"])]),
                                     /* Other build phases can be added here */
                                     /* .resources([.include(["./Resousrces /**/ *"])]) */
                          ]),
                      ])
        """.replacingOccurrences(of: "{{NAME}}", with: name)
    }
}
