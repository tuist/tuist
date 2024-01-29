import ProjectDescription

// Example of resources specified via variables instead of direct literals.
// Often sources and resources are declared in helpers where their values
// are computed, as such we need to support non-literal declarations.
let resourcesDirectory = "Resources"
let resources: [ResourceFileElement] = [
    "\(resourcesDirectory)/framework_resource.txt",
]

let project = Project(
    name: "Framework1",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    targets: [
        .target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            resources: .resources(resources)
        ),
    ]
)
