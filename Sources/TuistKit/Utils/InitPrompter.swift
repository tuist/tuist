import Foundation
import Mockable
import ServiceContextModule

struct InitPromptAnswers: Codable {
    let workflowType: InitPromptingWorkflowType
    let integrateWithServer: Bool
    let generatedProjectPlatform: String
    let generatedProjectName: String
    let accountType: InitPromptingAccountType
    let newOrganizationAccountHandle: String

    public init(
        workflowType: InitPromptingWorkflowType,
        integrateWithServer: Bool,
        generatedProjectPlatform: String,
        generatedProjectName: String,
        accountType: InitPromptingAccountType,
        newOrganizationAccountHandle: String
    ) {
        self.workflowType = workflowType
        self.integrateWithServer = integrateWithServer
        self.generatedProjectPlatform = generatedProjectPlatform
        self.generatedProjectName = generatedProjectName
        self.accountType = accountType
        self.newOrganizationAccountHandle = newOrganizationAccountHandle
    }

    func base64EncodedJSONString() throws -> String {
        let jsonData = try JSONEncoder().encode(self)
        return jsonData.base64EncodedString()
    }
}

enum InitPromptingWorkflowType: Codable, Equatable, CustomStringConvertible {
    case connectProjectOrSwiftPackage(String?)
    case createGeneratedProject

    var description: String {
        switch self {
        case let .connectProjectOrSwiftPackage(name):
            if let name {
                "Integrate with \(name)"
            } else {
                "Integrate the Xcode project or Swift Package"
            }
        case .createGeneratedProject: "Create a generated project"
        }
    }
}

enum InitPromptingAccountType: Codable, Equatable, CustomStringConvertible {
    case userAccount(String)
    case organization(String)
    case createOrganizationAccount

    var description: String {
        switch self {
        case let .userAccount(handle): "My personal account: '\(handle)'"
        case let .organization(handle): "Organization: \(handle)"
        case .createOrganizationAccount: "A new organization account"
        }
    }
}

@Mockable
protocol InitPrompting {
    func promptWorkflowType(xcodeProjectOrWorkspace: InitCommandService.XcodeProjectOrWorkspace?) -> InitPromptingWorkflowType
    func promptIntegrateWithServer() -> Bool
    func promptAccountType(authenticatedUserHandle: String, organizations: [String]) -> InitPromptingAccountType
    func promptNewOrganizationAccountHandle() -> String
    func promptGeneratedProjectPlatform() -> String
    func promptGeneratedProjectName() -> String
}

struct InitPrompter: InitPrompting {
    func promptAccountType(authenticatedUserHandle: String, organizations: [String]) -> InitPromptingAccountType {
        var promptOptions = [
            InitPromptingAccountType.userAccount(authenticatedUserHandle),
        ]
        promptOptions += organizations.map { InitPromptingAccountType.organization($0) }
        promptOptions.append(InitPromptingAccountType.createOrganizationAccount)
        return (ServiceContext.current?.ui?.singleChoicePrompt(
            title: "Account",
            question: "In which account would you like to create the project?",
            options: promptOptions
        ))!
    }

    func promptNewOrganizationAccountHandle() -> String {
        (ServiceContext.current?.ui?.textPrompt(
            title: "Organization handle",
            prompt: "Which handle would you like to use for the new organization account?",
            description: "We recommend hyphened lower-cased handles (e.g. my-organization)",
            collapseOnAnswer: true
        ))!
    }

    func promptWorkflowType(xcodeProjectOrWorkspace: InitCommandService.XcodeProjectOrWorkspace?) -> InitPromptingWorkflowType {
        let promptOptions = [
            InitPromptingWorkflowType.createGeneratedProject,
            InitPromptingWorkflowType.connectProjectOrSwiftPackage(xcodeProjectOrWorkspace?.name),
        ]
        return (ServiceContext.current?.ui?.singleChoicePrompt(
            title: "Start",
            question: "How would you like to start with Tuist?",
            options: promptOptions
        ))!
    }

    func promptIntegrateWithServer() -> Bool {
        ServiceContext.current?.ui?.yesOrNoChoicePrompt(
            title: "Server",
            question: "Would you like use server features (e.g. selective testing, previews)?",
            defaultAnswer: true,
            description: "You'll need to authenticate and create a project",
            collapseOnSelection: true
        ) ?? false
    }

    func promptGeneratedProjectPlatform() -> String {
        (ServiceContext.current?.ui?.singleChoicePrompt(
            title: "Platform",
            question: "Which platform would you like to generate code for?",
            options: [
                "iOS",
                "macOS",
                "tvOS",
                "watchOS",
            ],
            description: "The generated project's main target platform",
            collapseOnSelection: true
        ).lowercased())!
    }

    func promptGeneratedProjectName() -> String {
        (ServiceContext.current?.ui?.textPrompt(
            title: "Name",
            prompt: "How would you like to name the project?",
            description: "The name of the project and its main target",
            collapseOnAnswer: true
        ))!
    }
}
