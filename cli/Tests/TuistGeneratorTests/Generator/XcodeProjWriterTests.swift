
import FileSystem
import Foundation
import TuistCore
import TuistSupport
import XcodeProj
import FileSystemTesting
import Testing
@testable import TuistGenerator
@testable import TuistTesting

struct XcodeProjWriterTests {
    private let subject: XcodeProjWriter
    private let fileSystem: FileSysteming
    init() {
        subject = XcodeProjWriter()
        fileSystem = FileSystem()
    }

    @Test(.inTemporaryDirectory)
    func test_writeProject() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let descriptor = ProjectDescriptor.test(path: path, xcodeprojPath: xcodeProjPath)

        // When
        try await subject.write(project: descriptor)

        // Then
        let exists = try await fileSystem.exists(xcodeProjPath)
        #expect(exists)
    }

    @Test(.inTemporaryDirectory)
    func test_writeProject_fileSideEffects() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let filePath = path.appending(component: "MyFile")
        let expectedContents = "Testing".data(using: .utf8)!
        let sideEffect = SideEffectDescriptor.file(.init(
            path: filePath,
            contents: expectedContents
        ))
        let descriptor = ProjectDescriptor.test(
            path: path,
            xcodeprojPath: xcodeProjPath,
            sideEffects: [sideEffect]
        )

        // When
        try await subject.write(project: descriptor)

        // Then
        let exists = try await fileSystem.exists(filePath)
        #expect(exists)
        let contents = try await fileSystem.readFile(at: filePath)
        #expect(contents == expectedContents)
    }

    @Test(.inTemporaryDirectory)
    func test_writeProject_deleteFileSideEffects() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let filePath = path.appending(component: "MyFile")
        let fileHandler = FileHandler.shared
        try fileHandler.touch(filePath)

        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: filePath, state: .absent))
        let descriptor = ProjectDescriptor.test(
            path: path,
            xcodeprojPath: xcodeProjPath,
            sideEffects: [sideEffect]
        )

        // When
        try await subject.write(project: descriptor)

        // Then
        let exists = try await fileSystem.exists(filePath)
        #expect(!exists)
    }

    @Test(.inTemporaryDirectory)
    func test_generate_doesNotWipeUserData() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let paths = try await TuistTest.createFiles([
            "Foo.xcodeproj/xcuserdata/a",
            "Foo.xcodeproj/xcuserdata/b/c",
        ])

        let xcodeProjPath = path.appending(component: "Foo.xcodeproj")
        let descriptor = ProjectDescriptor.test(
            path: path,
            xcodeprojPath: xcodeProjPath
        )

        // When
        for _ in 0 ..< 2 {
            try await subject.write(project: descriptor)
        }

        // Then
        let exists = try await paths.concurrentMap { try await self.fileSystem.exists($0) }
        #expect(exists.allSatisfy { $0 })
    }

    @Test(.inTemporaryDirectory)
    func test_generate_replacesProjectSharedSchemes() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let schemeA = SchemeDescriptor.test(name: "SchemeA", shared: true)
        let schemeB = SchemeDescriptor.test(name: "SchemeB", shared: true)
        let schemeC = SchemeDescriptor.test(name: "SchemeC", shared: true)

        let schemesWriteOperations = [
            [schemeA, schemeB],
            [schemeA, schemeC],
        ]

        // When
        for schemes in schemesWriteOperations {
            let descriptor = ProjectDescriptor.test(
                path: path,
                xcodeprojPath: xcodeProjPath,
                schemes: schemes
            )
            try await subject.write(project: descriptor)
        }

        // Then
        let schemes = try await fileSystem.glob(directory: xcodeProjPath, include: ["**/*.xcscheme"]).collect().map(\.basename)
            .sorted()
        #expect(schemes == [
            "SchemeA.xcscheme",
            "SchemeC.xcscheme",
        ])
    }

    @Test(.inTemporaryDirectory)
    func test_generate_preservesProjectUserSchemes() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let userSchemeA = SchemeDescriptor.test(name: "UserSchemeA", shared: false)
        let userSchemeB = SchemeDescriptor.test(name: "UserSchemeB", shared: false)

        let schemesWriteOperations = [
            [userSchemeA],
            [userSchemeB],
        ]

        // When
        for schemes in schemesWriteOperations {
            let descriptor = ProjectDescriptor.test(
                path: path,
                xcodeprojPath: xcodeProjPath,
                schemes: schemes
            )
            try await subject.write(project: descriptor)
        }

        // Then
        let schemes = try await fileSystem.glob(directory: xcodeProjPath, include: ["**/*.xcscheme"]).collect().map(\.basename)
            .sorted()
        #expect(schemes == [
            "UserSchemeA.xcscheme",
            "UserSchemeB.xcscheme",
        ])
    }

    @Test(.inTemporaryDirectory)
    func test_generate_replacesWorkspaceSharedSchemes() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = path.appending(component: "Workspace.xcworkspace")
        let schemeA = SchemeDescriptor.test(name: "SchemeA", shared: true)
        let schemeB = SchemeDescriptor.test(name: "SchemeB", shared: true)
        let schemeC = SchemeDescriptor.test(name: "SchemeC", shared: true)

        let schemesWriteOperations = [
            [schemeA, schemeB],
            [schemeA, schemeC],
        ]

        // When
        for schemes in schemesWriteOperations {
            let descriptor = WorkspaceDescriptor.test(
                path: path,
                xcworkspacePath: xcworkspacePath,
                schemes: schemes
            )
            try await subject.write(workspace: descriptor)
        }

        // Then
        let schemes = try await fileSystem.glob(directory: xcworkspacePath, include: ["**/*.xcscheme"]).collect().map(\.basename)
            .sorted()
        #expect(schemes == [
            "SchemeA.xcscheme",
            "SchemeC.xcscheme",
        ])
    }

    @Test(.inTemporaryDirectory)
    func test_generate_preservesWorkspaceUserSchemes() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = path.appending(component: "Workspace.xcworkspace")
        let userSchemeA = SchemeDescriptor.test(name: "UserSchemeA", shared: false)
        let userSchemeB = SchemeDescriptor.test(name: "UserSchemeB", shared: false)

        let schemesWriteOperations = [
            [userSchemeA],
            [userSchemeB],
        ]

        // When
        for schemes in schemesWriteOperations {
            let descriptor = WorkspaceDescriptor.test(
                path: path,
                xcworkspacePath: xcworkspacePath,
                schemes: schemes
            )
            try await subject.write(workspace: descriptor)
        }

        // Then
        let schemes = try await fileSystem.glob(directory: xcworkspacePath, include: ["**/*.xcscheme"]).collect().map(\.basename)
            .sorted()
        #expect(schemes == [
            "UserSchemeA.xcscheme",
            "UserSchemeB.xcscheme",
        ])
    }

    @Test(.inTemporaryDirectory)
    func test_generate_local_scheme() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let userScheme = SchemeDescriptor.test(name: "UserScheme", shared: false)
        let descriptor = ProjectDescriptor.test(path: path, xcodeprojPath: xcodeProjPath, schemes: [userScheme])

        // When
        try await subject.write(project: descriptor)

        // Then
        let username = NSUserName()
        let schemesPath = xcodeProjPath.appending(components: "xcuserdata", "\(username).xcuserdatad", "xcschemes")
        let schemes = try await fileSystem.glob(directory: schemesPath, include: ["*.xcscheme"]).collect().map(\.basename)
            .sorted()
        #expect(schemes == [
            "UserScheme.xcscheme",
        ])
    }
}
