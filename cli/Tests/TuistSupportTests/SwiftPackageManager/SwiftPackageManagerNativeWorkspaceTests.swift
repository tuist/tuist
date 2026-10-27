import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistTesting
@testable import TuistSupport

struct SwiftPackageManagerNativeWorkspaceTests {
    @Test(.inTemporaryDirectory, arguments: [false, true])
    func packagePathOverrideSelectsDefaultScratch(relativePath: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let package = root.appending(component: "package")
        let alternate = root.appending(component: "alternate")
        let source = root.appending(component: "source")
        let checkout = alternate.appending(components: ".build", "checkouts", "Dependency")
        let untouched = package.appending(components: ".build", "checkouts", "Dependency")
        try await fileSystem.makeDirectory(at: source, options: [.createTargetParentDirectories])
        try await fileSystem.writeText("original", at: source.appending(component: "file"))
        for link in [checkout, untouched] {
            try await fileSystem.makeDirectory(at: link.parentDirectory, options: [.createTargetParentDirectories])
            try await fileSystem.createSymbolicLink(from: link, to: source)
        }
        let path = relativePath ? alternate.relative(to: try await fileSystem.currentWorkingDirectory()).pathString : alternate
            .pathString
        let arguments = ["--package-path=\(path)"]
        let command = ["swift", "package", "--package-path", package.pathString] + arguments + ["resolve"]
        let runner = MockCommandRunner()
        runner.succeedCommand(command)
        let controller = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { runner },
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "0"] }
        )
        try await controller.resolve(at: package, arguments: arguments, printOutput: false)
        try await fileSystem.writeText("private edit", at: checkout.appending(component: "file"))
        #expect(try await fileSystem.readFile(at: source.appending(component: "file")) == Data("original".utf8))
        #expect(try await fileSystem.readFile(at: untouched.appending(component: "file")) == Data("original".utf8))
    }

    @Test(.inTemporaryDirectory, arguments: [false, true], ["--scratch-path", "--scratch-path=", "--build-path", "--build-path="])
    func nativeDelegationPrivatizesEffectiveScratchOnly(update: Bool, flag: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let package = root.appending(component: "package")
        let alternatePackage = root.appending(component: "alternate")
        let scratch = root.appending(component: "scratch")
        let source = root.appending(component: "source")
        let checkout = scratch.appending(components: "checkouts", "Dependency")
        let untouched = package.appending(components: ".build", "checkouts", "Dependency")
        try await fileSystem.makeDirectory(at: source, options: [.createTargetParentDirectories])
        try await fileSystem.writeText("original", at: source.appending(component: "file"))
        for link in [checkout, untouched] {
            try await fileSystem.makeDirectory(at: link.parentDirectory, options: [.createTargetParentDirectories])
            try await fileSystem.createSymbolicLink(from: link, to: source)
        }
        let scratchArguments = flag.hasSuffix("=") ? [flag + scratch.pathString] : [flag, scratch.pathString]
        let arguments = ["--package-path=\(alternatePackage.pathString)"] + scratchArguments
        let command = ["swift", "package", "--package-path", package.pathString] + arguments + [update ? "update" : "resolve"]
        let runner = MockCommandRunner()
        runner.succeedCommand(command)
        let controller = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { runner },
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "0"] }
        )
        if update {
            try await controller.update(at: package, arguments: arguments, printOutput: false)
        } else {
            try await controller.resolve(at: package, arguments: arguments, printOutput: false)
        }
        #expect(runner.called(command))
        #expect(try await fileSystem.readFile(at: checkout.appending(component: "file")) == Data("original".utf8))
        try await fileSystem.writeText("private edit", at: checkout.appending(component: "file"))
        #expect(try await fileSystem.readFile(at: source.appending(component: "file")) == Data("original".utf8))
        #expect(try await fileSystem.readFile(at: untouched.appending(component: "file")) == Data("original".utf8))
    }
}
