import ProjectDescription

func frameworkName() -> String {
    if case let .string(environmentFrameworkName) = Environment.frameworkName {
        return environmentFrameworkName
    } else {
        return "Framework"
    }
}

let project = Project(name: "Framework",
                      targets: [
                          Target(name: frameworkName(),
                                 platform: .macOS,
                                 product: .framework,
                                 bundleId: "io.tuist.App",
                                 infoPlist: .default,
                                 sources: .paths([.relativeToManifest("Sources/**")]))
])
