
import Foundation
import TSCBasic
import TuistCore
import TuistGeneratorTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class XcodeProjWriterTests: TuistTestCase {
    private var subject: XcodeProjWriter!

    override func setUp() {
        super.setUp()
        subject = XcodeProjWriter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_writeProject() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let descriptor = ProjectDescriptor.test(path: path, xcodeprojPath: xcodeProjPath)

        // When
        try subject.write(project: descriptor)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(xcodeProjPath))
    }

    func test_writeProject_fileSideEffects() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let filePath = path.appending(component: "MyFile")
        let contents = "Testing".data(using: .utf8)!
        let sideEffect = SideEffectDescriptor.file(.init(
            path: filePath,
            contents: contents
        ))
        let descriptor = ProjectDescriptor.test(
            path: path,
            xcodeprojPath: xcodeProjPath,
            sideEffects: [sideEffect]
        )

        // When
        try subject.write(project: descriptor)

        // Then
        let fileHandler = FileHandler.shared
        XCTAssertTrue(fileHandler.exists(filePath))
        XCTAssertEqual(try fileHandler.readFile(filePath), contents)
    }

    func test_writeProject_deleteFileSideEffects() throws {
        // Given
        let path = try temporaryPath()
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
        try subject.write(project: descriptor)

        // Then
        XCTAssertFalse(fileHandler.exists(filePath))
    }

    func test_generate_doesNotWipeUserData() throws {
        // Given
        let path = try temporaryPath()
        let paths = try createFiles([
            "Foo.xcodeproj/xcuserdata/a",
            "Foo.xcodeproj/xcuserdata/b/c",
        ])

        let xcodeProjPath = path.appending(component: "Foo.xcodeproj")
        let descriptor = ProjectDescriptor.test(
            path: path,
            xcodeprojPath: xcodeProjPath
        )

        // When
        try (0 ..< 2).forEach { _ in
            try subject.write(project: descriptor)
        }

        // Then
        XCTAssertTrue(paths.allSatisfy { FileHandler.shared.exists($0) })
    }

    func test_generate_replacesProjectSharedSchemes() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let schemeA = SchemeDescriptor.test(name: "SchemeA", shared: true)
        let schemeB = SchemeDescriptor.test(name: "SchemeB", shared: true)
        let schemeC = SchemeDescriptor.test(name: "SchemeC", shared: true)

        let schemesWriteOperations = [
            [schemeA, schemeB],
            [schemeA, schemeC],
        ]

        // When
        try schemesWriteOperations.forEach { schemes in
            let descriptor = ProjectDescriptor.test(
                path: path,
                xcodeprojPath: xcodeProjPath,
                schemes: schemes
            )
            try subject.write(project: descriptor)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemes = fileHandler.glob(xcodeProjPath, glob: "**/*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "SchemeA.xcscheme",
            "SchemeC.xcscheme",
        ])
    }

    func test_generate_preservesProjectUserSchemes() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let userSchemeA = SchemeDescriptor.test(name: "UserSchemeA", shared: false)
        let userSchemeB = SchemeDescriptor.test(name: "UserSchemeB", shared: false)

        let schemesWriteOperations = [
            [userSchemeA],
            [userSchemeB],
        ]

        // When
        try schemesWriteOperations.forEach { schemes in
            let descriptor = ProjectDescriptor.test(
                path: path,
                xcodeprojPath: xcodeProjPath,
                schemes: schemes
            )
            try subject.write(project: descriptor)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemes = fileHandler.glob(xcodeProjPath, glob: "**/*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "UserSchemeA.xcscheme",
            "UserSchemeB.xcscheme",
        ])
    }

    func test_generate_replacesWorkspaceSharedSchemes() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Workspace.xcworkspace")
        let schemeA = SchemeDescriptor.test(name: "SchemeA", shared: true)
        let schemeB = SchemeDescriptor.test(name: "SchemeB", shared: true)
        let schemeC = SchemeDescriptor.test(name: "SchemeC", shared: true)

        let schemesWriteOperations = [
            [schemeA, schemeB],
            [schemeA, schemeC],
        ]

        // When
        try schemesWriteOperations.forEach { schemes in
            let descriptor = WorkspaceDescriptor.test(
                path: path,
                xcworkspacePath: xcworkspacePath,
                schemes: schemes
            )
            try subject.write(workspace: descriptor)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemes = fileHandler.glob(xcworkspacePath, glob: "**/*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "SchemeA.xcscheme",
            "SchemeC.xcscheme",
        ])
    }

    func test_generate_preservesWorkspaceUserSchemes() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Workspace.xcworkspace")
        let userSchemeA = SchemeDescriptor.test(name: "UserSchemeA", shared: false)
        let userSchemeB = SchemeDescriptor.test(name: "UserSchemeB", shared: false)

        let schemesWriteOperations = [
            [userSchemeA],
            [userSchemeB],
        ]

        // When
        try schemesWriteOperations.forEach { schemes in
            let descriptor = WorkspaceDescriptor.test(
                path: path,
                xcworkspacePath: xcworkspacePath,
                schemes: schemes
            )
            try subject.write(workspace: descriptor)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemes = fileHandler.glob(xcworkspacePath, glob: "**/*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "UserSchemeA.xcscheme",
            "UserSchemeB.xcscheme",
        ])
    }

    func test_generate_local_scheme() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let userScheme = SchemeDescriptor.test(name: "UserScheme", shared: false)
        let descriptor = ProjectDescriptor.test(path: path, xcodeprojPath: xcodeProjPath, schemes: [userScheme])

        // When
        try subject.write(project: descriptor)

        // Then
        let fileHandler = FileHandler.shared
        let username = NSUserName()
        let schemesPath = xcodeProjPath.appending(components: "xcuserdata", "\(username).xcuserdatad", "xcschemes")
        let schemes = fileHandler.glob(schemesPath, glob: "*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "UserScheme.xcscheme",
        ])
    }
}
