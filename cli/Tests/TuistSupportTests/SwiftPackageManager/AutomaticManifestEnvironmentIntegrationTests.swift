import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistProcess
@testable import TuistSupport

struct AutomaticManifestEnvironmentIntegrationTests {
    @Test(.inTemporaryDirectory, arguments: [true, false], [true, false])
    func automatic_resolves_authenticated_git_dependencies_without_overrides(embedded: Bool, update: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let runner = CommandRunner()
        let dependency = root.appending(component: "Dependency")
        let package = root.appending(component: "App")
        let home = root.appending(component: "home")
        for directory in [dependency, package, home] {
            try await fileSystem.makeDirectory(at: directory)
        }
        try await fileSystem.writeText("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Dependency")
        """, at: dependency.appending(component: "Package.swift"))
        for arguments in [
            ["init"], ["add", "."],
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "fixture"],
            ["tag", "1.0.0"],
        ] {
            try await runner.runAndWait(arguments: [
                "git",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.hooksPath=/dev/null",
                "-C",
                dependency.pathString,
            ] + arguments)
        }
        try await fileSystem.writeText("""
        // swift-tools-version: 6.0
        import PackageDescription
        precondition(Context.environment["GITHUB_REF"] == nil)
        precondition(Context.environment["GITHUB_SHA"] == nil)
        let package = Package(name: "App", dependencies: [
            .package(url: "ssh://git@fixture\(dependency.pathString)", exact: "1.0.0")
        ])
        """, at: package.appending(component: "Package.swift"))
        let ssh = root.appending(component: "ssh-fixture")
        let receipt = root.appending(component: "authenticated")
        try await fileSystem.writeText("""
        #!/bin/sh
        set -eu
        case "$GITHUB_TOKEN" in first-token|second-token) ;; *) exit 90 ;; esac
        case "$SSH_AUTH_SOCK" in /first-agent.sock|/second-agent.sock) ;; *) exit 91 ;; esac
        case "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" in first-oidc|second-oidc) ;; *) exit 92 ;; esac
        test -n "$ACTIONS_ID_TOKEN_REQUEST_URL"
        printf authenticated > '\(receipt.pathString)'
        for argument do command="$argument"; done
        exec /bin/sh -c "$command"
        """, at: ssh)
        try await runner.runAndWait(arguments: ["chmod", "+x", ssh.pathString])

        var firstFingerprint: String?
        for job in ["first", "second"] {
            var variables = ProcessInfo.processInfo.environment
            variables["HOME"] = home.pathString
            variables["SWIFTPM_MIRROR_CONFIG"] = nil
            variables["GIT_CONFIG_NOSYSTEM"] = "1"
            variables["GIT_CONFIG_GLOBAL"] = "/dev/null"
            variables["GIT_SSH_COMMAND"] = "'\(ssh.pathString)'"
            variables["GIT_SSH_VARIANT"] = "ssh"
            variables["TUIST_USE_SWIFTERPM"] = embedded ? "1" : "0"
            variables["GITHUB_ACTIONS"] = "true"
            variables["GITHUB_REF"] = "refs/heads/\(job)"
            variables["GITHUB_SHA"] = "\(job)-commit"
            variables["GITHUB_TOKEN"] = "\(job)-token"
            variables["SSH_AUTH_SOCK"] = "/\(job)-agent.sock"
            variables["ACTIONS_ID_TOKEN_REQUEST_TOKEN"] = "\(job)-oidc"
            variables["ACTIONS_ID_TOKEN_REQUEST_URL"] = "https://issuer.example/\(job)"
            variables["TUIST_CACHE_SIGNING_GRANT"] = "\(job)-grant"
            variables["TUIST_RUNNER_POD_UID"] = "\(job)-pod"
            let environment = variables
            let controller = SwiftPackageManagerController(
                fileSystem: fileSystem,
                commandRunner: { CommandRunner() },
                environmentVariables: { environment }
            )
            try await PackageManifestEnvironment.withConfiguration(.init()) {
                var arguments = ["--disable-sandbox", "--cache-path", root.appending(component: "cache").pathString]
                if job == "second", !update { arguments.append("--force-resolved-versions") }
                if update, job == "second" {
                    try await controller.update(at: package, arguments: arguments, printOutput: false)
                } else {
                    try await controller.resolve(at: package, arguments: arguments, printOutput: false)
                }
            }
            #expect(try await fileSystem.readTextFile(at: receipt) == "authenticated")
            let lockfile = try await fileSystem.readTextFile(at: package.appending(component: "Package.resolved"))
            #expect(lockfile.contains("1.0.0"))
            if embedded {
                let fingerprint = try await fileSystem.readTextFile(
                    at: package.appending(components: ".build", "swifterpm", "manifests", "package.json.inputs.json")
                )
                if let firstFingerprint {
                    #expect(fingerprint == firstFingerprint)
                } else {
                    firstFingerprint = fingerprint
                }
            }
        }
    }
}
