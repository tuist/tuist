import ArgumentParser
import TuistSupport
import TuistServer
import TuistLoader
import FileSystem
import XCLogParser
import Foundation

struct InspectBuildCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Inspects the latest build."
        )
    }

//    @Option(
//        name: .shortAndLong,
//        help: "The path to the directory that contains the project.",
//        completion: .directory,
//        envKey: .lintImplicitDependenciesPath
//    )
//    var path: String?

    func run() async throws {
        try await InspectBuildService()
            .run()
    }
}

struct InspectBuildService {
    private let environment: Environmenting
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    
    init(
        environment: Environmenting = Environment.shared,
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.environment = environment
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
    }
    
    func run() async throws {
        let workspacePath = environment.workspacePath!
        let config = try await ConfigLoader(warningController: WarningController.shared)
            .loadConfig(path: workspacePath)
        let buildLogsPath = try derivedDataLocator.locate(for: workspacePath.parentDirectory)
            .appending(components: "Logs", "Build")
        let plist: LogStoreManifest = try await fileSystem.readPlistFile(at: buildLogsPath.appending(component: "LogStoreManifest.plist"))
        let latestLog = plist.logs.values.sorted(by: { $0.timeStoppedRecording > $1.timeStoppedRecording }).first!
        let logPath = buildLogsPath.appending(component: latestLog.fileName)
        let activityLog = try ActivityParser().parseActivityLogInURL(
            logPath.url,
            redacted: false,
            withoutBuildSpecificInformation: false
        )
        try! await CreateBuildService().createBuild(
            fullHandle: config.fullHandle!,
            serverURL: config.url,
            duration: Int(activityLog.mainSection.timeStoppedRecording) - Int(activityLog.mainSection.timeStartedRecording)
        )
    }
}

struct ActivityLog: Codable {
    let fileName: String
    let timeStartedRecording: Double
    let timeStoppedRecording: Double
}

struct LogStoreManifest: Codable {
    let logs: [String: ActivityLog]
}
