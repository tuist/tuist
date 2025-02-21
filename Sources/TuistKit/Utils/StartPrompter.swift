import ServiceContextModule

enum StartPromptingWorkflowType: Equatable, CustomStringConvertible {
    case integrateWithProjectOrWorkspace(String)
    case createGeneratedProject

    var description: String {
        switch self {
        case let .integrateWithProjectOrWorkspace(name): "Integrate with \(name)"
        case .createGeneratedProject: "Create a generated project"
        }
    }
}

protocol StartPrompting {
    func promptWorkflowType(xcodeProjectOrWorkspace: StartService.XcodeProjectOrWorkspace?) -> StartPromptingWorkflowType!
    func promptIntegrateWithServer() -> Bool
    func promptGeneratedProjectPlatform() -> String!
    func promptGeneratedProjectName() -> String!
}

struct StartPrompter: StartPrompting {

    func promptWorkflowType(xcodeProjectOrWorkspace: StartService.XcodeProjectOrWorkspace?) -> StartPromptingWorkflowType! {
        var promptOptions = [
            StartPromptingWorkflowType.createGeneratedProject,
        ]
        if let xcodeProjectOrWorkspace {
            promptOptions.append(.integrateWithProjectOrWorkspace(xcodeProjectOrWorkspace.name))
        }
        return ServiceContext.current?.ui?.singleChoicePrompt(
            title: "Start",
            question: "How would you like to start with Tuist?",
            options: promptOptions
        )
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

    func promptGeneratedProjectPlatform() -> String! {
        ServiceContext.current?.ui?.singleChoicePrompt(
            title: "Platform",
            question: "Which platform would you like to generate code for?",
            options: [
                "macOS",
                "iOS",
                "tvOS",
                "watchOS",
            ],
            description: "The generated project's main target platform",
            collapseOnSelection: true
        ).lowercased()
    }

    func promptGeneratedProjectName() -> String! {
        ServiceContext.current?.ui?.textPrompt(
            title: "Name",
            prompt: "How would you like to name the project?",
            description: "The name of the project and its main target",
            collapseOnAnswer: true
        )
    }
}
