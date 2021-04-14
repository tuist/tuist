
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

    func test_generate_replacesSchemes() throws {
        // Given
        let path = try temporaryPath()
        let xcodeProjPath = path.appending(component: "Project.xcodeproj")
        let schemeA = SchemeDescriptor.test(name: "SchemeA", shared: true)
        let schemeB = SchemeDescriptor.test(name: "SchemeB", shared: true)
        let userScheme = SchemeDescriptor.test(name: "UserScheme", shared: false)

        let schemesWriteOperations = [
            [schemeA, schemeB],
            [schemeA, userScheme],
        ]

        // When
        try schemesWriteOperations.forEach {
            let descriptor = ProjectDescriptor.test(
                path: path,
                xcodeprojPath: xcodeProjPath,
                schemes: $0
            )
            try subject.write(project: descriptor)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemes = fileHandler.glob(xcodeProjPath, glob: "**/*.xcscheme").map(\.basename)
        XCTAssertEqual(schemes, [
            "SchemeA.xcscheme",
            "UserScheme.xcscheme",
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
