import Foundation
import Basic

class Scheme: JSONMappable {
    let name: String
    let shared: Bool
    let buildAction: BuildAction?
    let testAction: TestAction?
    let runAction: RunAction?

    required init(json: JSON) throws {
        name = try json.get("name")
        shared = try json.get("shared")
        buildAction = json.get("build_action")
        testAction = json.get("test_action")
        runAction = json.get("run_action")
    }
}

class Arguments: JSONMappable {
    let environment: [String: String]
    let launch: [String: Bool]

    required init(json: JSON) throws {
        environment = try json.get("environment")
        launch = try json.get("launch")
    }
}

public class BuildAction: JSONMappable {
    let targets: [String]

    public required init(json: JSON) throws {
        targets = try json.get("targets")
    }
}

public class TestAction: JSONMappable {
    let targets: [String]
    let arguments: Arguments?
    let config: BuildConfiguration
    let coverage: Bool

    public required init(json: JSON) throws {
        targets = try json.get("targets")
        arguments = json.get("arguments")
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        coverage = try json.get("coverage")
    }
}

class RunAction: JSONMappable {
    let config: BuildConfiguration
    let executable: String?
    let arguments: Arguments?

    required init(json: JSON) throws {
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        executable = json.get("executable")
        arguments = json.get("arguments")
    }
}
