import Basic
import Foundation
import TuistCore
import xcodeproj

protocol SchemeGenerating: AnyObject {
    func generateSchemes(project: Project,
                         xcodeprojPath: AbsolutePath,
                         nativeTargets: [String: PBXNativeTarget],
                         generationOptions: GenerationOptions) throws
}

enum SchemeGeneratorError: FatalError {
    case missingTarget(String, projectPath: AbsolutePath)
    case temporaryTargetReference(String)

    var description: String {
        switch self {
        case let .missingTarget(targetName, projectPath):
            return "Project at path \(projectPath) has no target named \(targetName)"
        case let .temporaryTargetReference(targetName):
            return "Can't generate a scheme reference to the target \(targetName) whose reference is temporary "
        }
    }

    var type: ErrorType {
        switch self {
        case .missingTarget: return .bug
        case .temporaryTargetReference:
            return bug
        }
    }
}

final class SchemeGenerator: SchemeGenerating {

    // MARK: - Attributes

    let fileHandler: FileHandling

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    // MARK: - SchemeGenerating

    func generateSchemes(project: Project,
                         xcodeprojPath: AbsolutePath,
                         nativeTargets: [String: PBXNativeTarget],
                         generationOptions: GenerationOptions) throws {
        let sharedDataPath = xcodeprojPath.appending(component: "xcshareddata")
        let schemesPath = sharedDataPath.appending(component: "xcschemes")

        try fileHandler.createFolder(sharedDataPath)
        try fileHandler.createFolder(schemesPath)

        try project.targets.forEach {
            try generateScheme(target: $0, project: project, schemesPath: schemesPath, nativeTargets: nativeTargets, generationOptions: generationOptions)
        }
        try generateAllScheme(targets: project.targets, schemesPath: schemesPath)
    }

    func generateScheme(target: Target,
                        project: Project,
                        schemesPath: AbsolutePath,
                        nativeTargets: [String: PBXNativeTarget],
                        generationOptions: GenerationOptions) throws {
        guard let nativeTarget = nativeTargets[target.name] else {
            throw SchemeGeneratorError.missingTarget(target.name, projectPath: project.path)
        }
        nativeTarget.reference.hashValue

        let buildableReference = XCScheme.BuildableReference(referencedContainer: "container:\(project.name).xcodeproj",
                                                             blueprintIdentifier: "id", // the uuid TODO
                                                             buildableName: "name", // asdgas.app or asdgas.xctest TODO
                                                             blueprintName: target.name,
                                                             buildableIdentifier: "primary")

        let buildEntry = XCScheme.BuildAction.Entry(buildableReference: buildableReference,
                                                    buildFor: [.testing, .running, .profiling, .archiving, .analyzing])
        let buildAction = XCScheme.BuildAction(buildActionEntries: [buildEntry],
                                               preActions: [],
                                               postActions: [],
                                               parallelizeBuild: true,
                                               buildImplicitDependencies: true)
//        <TestAction
//        buildConfiguration = "Debug"
//        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
//        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
//        shouldUseLaunchSchemeArgsEnv = "YES">
//        <Testables>
//        </Testables>
//        <MacroExpansion>
//        <BuildableReference
//        BuildableIdentifier = "primary"
//        BlueprintIdentifier = "6DB1A02D311C8AFF0EE2E039495B4D78"
//        BuildableName = "Downloads.app"
//        BlueprintName = "Downloads"
//        ReferencedContainer = "container:Downloads.xcodeproj">
//        </BuildableReference>
//        </MacroExpansion>
//        <AdditionalOptions>
//        </AdditionalOptions>
//        </TestAction>

        let launchAction = XCScheme.LaunchAction(buildableProductRunnable: nil,
                                                 buildConfiguration: generationOptions.buildConfiguration.xcodeValue,
                                                 selectedDebuggerIdentifier: XCScheme.defaultDebugger,
                                                 selectedLauncherIdentifier: XCScheme.defaultLauncher,
                                                 launchStyle: .auto,
                                                 useCustomWorkingDirectory: false,
                                                 ignoresPersistentStateOnLaunch: false,
                                                 debugDocumentVersioning: true,
                                                 debugServiceExtension: "internal",
                                                 allowLocationSimulation: true)

        let profileAction = XCScheme.ProfileAction(buildableProductRunnable: nil,
                                                   buildConfiguration: generationOptions.buildConfiguration.xcodeValue,
                                                   shouldUseLaunchSchemeArgsEnv: true,
                                                   savedToolIdentifier: "",
                                                   useCustomWorkingDirectory: false,
                                                   debugDocumentVersioning: true)

        let analyzeAction = XCScheme.AnalyzeAction(buildConfiguration: generationOptions.buildConfiguration.xcodeValue)

        let archiveAction = XCScheme.ArchiveAction(buildConfiguration: generationOptions.buildConfiguration.xcodeValue,
                                                   revealArchiveInOrganizer: true)

        let scheme = XCScheme(name: target.name,
                              lastUpgradeVersion: Constants.schemeLastUpgradeVersion,
                              version: Constants.version,
                              buildAction: buildAction,
                              testAction: nil,
                              launchAction: launchAction,
                              profileAction: profileAction,
                              analyzeAction: analyzeAction,
                              archiveAction: archiveAction)

        let schemePath = schemesPath.appending(component: "\(target.name).xcscheme")
        try scheme.write(path: schemePath, override: true)
    }

    func generateAllScheme(targets _: [Target], schemesPath _: AbsolutePath) throws {
        // TODO:
    }
}
