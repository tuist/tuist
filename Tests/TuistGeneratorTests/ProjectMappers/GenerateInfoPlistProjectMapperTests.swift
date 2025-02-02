import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class GenerateInfoPlistProjectMapperTests: TuistUnitTestCase {
    var infoPlistContentProvider: MockInfoPlistContentProvider!
    var sideEffectExecutor: SideEffectDescriptorExecutor!
    var subject: GenerateInfoPlistProjectMapper!

    override public func setUp() {
        super.setUp()
        infoPlistContentProvider = MockInfoPlistContentProvider()
        sideEffectExecutor = SideEffectDescriptorExecutor()
        subject = GenerateInfoPlistProjectMapper(
            infoPlistContentProvider: infoPlistContentProvider,
            derivedDirectoryName: Constants.DerivedDirectory.name,
            infoPlistsDirectoryName: Constants.DerivedDirectory.infoPlists
        )
    }

    override public func tearDown() {
        infoPlistContentProvider = nil
        sideEffectExecutor = nil
        subject = nil
        super.tearDown()
    }

    func test_map() throws {
        // Given
        let targetA = Target.test(name: "A", infoPlist: .dictionary(["A": "A_VALUE"]))
        let targetB = Target.test(name: "B", infoPlist: .dictionary(["B": "B_VALUE"]))
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(sideEffects.count, 2)
        XCTAssertEqual(mappedProject.targets.count, 2)

        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Info.plist",
            content: ["A": "A_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "B-Info.plist",
            content: ["B": "B_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "A-Info.plist",
            project: mappedProject
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "B-Info.plist",
            project: mappedProject
        )
    }

    func test_map_when_extendingFile() async throws {
        // Given
        let baseInfoPlistContent: [String: Plist.Value] = [
            "CFBundleIdentifier": .string("com.example.app"),
            "CFBundleShortVersionString": .string("1.0"),
        ]
        let extendingPlistContent: [String: Plist.Value] = [
            "CFBundleShortVersionString": .string("2.0"),
            "NewCustomKey": .string("NewCustomValue"),
        ]
        let expectedPlistContent: [String: Plist.Value] = [
            "CFBundleIdentifier": .string("com.example.app"),
            "CFBundleShortVersionString": .string("2.0"), // this must be overridden
            "NewCustomKey": .string("NewCustomValue"), // this must be added
        ]

        let tempPath = try temporaryPath()

        let targetA = Target.test(
            name: "TargetA",
            infoPlist: .dictionary(baseInfoPlistContent)
        )
        let projectA = Project.test(
            path: tempPath,
            targets: [targetA]
        )

        // When
        let (_, sideEffectsA) = try subject.map(project: projectA)
        try await sideEffectExecutor.execute(sideEffects: sideEffectsA)

        let generatedTargetAInfoPlistFilePath = sideEffectsA.compactMap {
            if case let .file(fileDescriptor) = $0 { fileDescriptor.path } else { nil }
        }.first!

        let targetB = Target.test(
            name: "TargetB",
            infoPlist: .extendingFile(
                path: generatedTargetAInfoPlistFilePath,
                with: extendingPlistContent
            )
        )
        let projectB = Project.test(
            path: tempPath,
            targets: [targetB]
        )

        let (mappedProjectB, sideEffectsB) = try subject.map(project: projectB)
        try await sideEffectExecutor.execute(sideEffects: sideEffectsB)

        // Then
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "TargetB-Info.plist",
            content: expectedPlistContent.mapValues { $0.value as! String },
            projectPath: projectB.path,
            sideEffects: sideEffectsB
        )

        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "TargetB-Info.plist",
            project: mappedProjectB
        )
    }

    // MARK: - Helpers

    private func XCTAssertSideEffectsCreateDerivedInfoPlist(
        named: String,
        content: [String: String],
        projectPath: AbsolutePath,
        sideEffects: [SideEffectDescriptor],
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: content,
            format: .xml,
            options: 0
        )

        XCTAssertNotNil(sideEffects.first(where: { sideEffect in
            guard case let SideEffectDescriptor.file(file) = sideEffect else { return false }
            return file.path == projectPath
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named) && file.contents == data
        }), file: file, line: line)
    }

    private func XCTAssertTargetExistsWithDerivedInfoPlist(
        named: String,
        project: Project,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertNotNil(project.targets.values.first(where: { (target: Target) in
            target.infoPlist?.path == project.path
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named)
        }), file: file, line: line)
    }
}
