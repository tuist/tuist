import ProjectDescription

let project = Project(
    name: "ClangChunkFixture",
    settings: .settings(base: [
        "CODE_SIGNING_ALLOWED": "NO",
        "COMPILATION_CACHE_ENABLE_PLUGIN": "YES",
        "COMPILATION_CACHE_PLUGIN_PATH": "$(TUIST_XCODE_TEST_PLUGIN)",
        "COMPILATION_CACHE_REMOTE_SERVICE_PATH": "$(TUIST_XCODE_TEST_SOCKET)",
        "COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS": "YES",
        "OTHER_CFLAGS": "$(inherited) -Xclang -fcas-plugin-option -Xclang tuist-instance=$(TUIST_XCODE_TEST_INSTANCE)",
        "CLANG_ENABLE_MODULES": "NO",
    ]),
    targets: [
        .target(
            name: "ClangChunkFixture",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.ClangChunkFixture",
            deploymentTargets: .macOS("15.0"),
            sources: ["Fixture.c"]
        ),
    ]
)
