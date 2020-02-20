import ProjectDescription

// 0. Implement the Environment
enum Environment : String {
    case dev, staging, production
    
    private var configuration : String { rawValue.capitalized }
    
    private var nameSuffix : String {
        switch self {
        case .production: return "" // no target name change for production
        default: return rawValue.capitalized
        }
    }
    
    static func all() -> [Environment] { [.dev, .staging, .production] }
    
    func makeScheme(named name: String) -> Scheme {
        let buildAction = BuildAction(targets: [.init(stringLiteral: name)])
        let runAction = RunAction(configurationName: configuration)
        
        return Scheme(name: name + nameSuffix, buildAction: buildAction, runAction: runAction)
    }
    
    func makeConfiguration() -> CustomConfiguration {
        switch self {
        case .production: return CustomConfiguration.release(name: configuration)
        default: return CustomConfiguration.debug(name: configuration)
        }
    }
}

// 1. make environments
let environments = Environment.all()

// 2. make configurations
let configurations = environments.map { $0.makeConfiguration() }

// 3. make schemes
let schemes = environments.map { $0.makeScheme(named: "App") }

// 4. Make settings
let settings = Settings(base: [
    "PROJECT_BASE": "PROJECT_BASE",
], configurations: configurations)

// 5. Make Project
let project = Project(name: "MainApp",
                      settings: settings,
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Support/App-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework1", path: "../Framework1"),
                                     .project(target: "Framework2", path: "../Framework2"),
                          ]),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Support/AppTests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                          ]),
                      ], schemes: schemes)
