import ProjectDescription

let project = Project(
    name: "LookupFixture",
    settings: .settings(
        base: [
            "CODE_SIGNING_ALLOWED": "NO",
            "COMPILATION_CACHE_ENABLE_PLUGIN": "YES",
            "COMPILATION_CACHE_PLUGIN_PATH": "$(TUIST_XCODE_TEST_PLUGIN)",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": "$(TUIST_XCODE_TEST_SOCKET)",
            "COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS": "YES",
            "OTHER_SWIFT_FLAGS": "$(inherited) -cas-plugin-option tuist-instance=$(TUIST_XCODE_TEST_INSTANCE)",
            "SWIFT_ENABLE_EXPLICIT_MODULES": "YES",
            "SWIFT_VERSION": "6.0",
        ]
    ),
    targets: [
        .target(
            name: "LookupFixture",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.LookupFixture",
            deploymentTargets: .macOS("15.0"),
            sources: ["Fixture.swift"]
        ),
    ]
)
