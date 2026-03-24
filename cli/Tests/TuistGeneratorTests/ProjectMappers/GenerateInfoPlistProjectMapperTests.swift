import Foundation
import Path
import Testing
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator
@testable import TuistTesting

struct GenerateInfoPlistProjectMapperTests {
    let infoPlistContentProvider: MockInfoPlistContentProvider
    let subject: GenerateInfoPlistProjectMapper
    init() {
        infoPlistContentProvider = MockInfoPlistContentProvider()
        subject = GenerateInfoPlistProjectMapper(
            infoPlistContentProvider: infoPlistContentProvider,
            derivedDirectoryName: Constants.DerivedDirectory.name,
            infoPlistsDirectoryName: Constants.DerivedDirectory.infoPlists
        )
    }

    @Test
    func test_map() throws {
        // Given
        let targetA = Target.test(name: "A", infoPlist: .dictionary(["A": "A_VALUE"]))
        let targetB = Target.test(name: "B", infoPlist: .dictionary(["B": "B_VALUE"]))
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(sideEffects.count == 2)
        #expect(mappedProject.targets.count == 2)

        try assertSideEffectsCreateDerivedInfoPlist(
            named: "A-Info.plist",
            content: ["A": "A_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try assertSideEffectsCreateDerivedInfoPlist(
            named: "B-Info.plist",
            content: ["B": "B_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        assertTargetExistsWithDerivedInfoPlist(
            named: "A-Info.plist",
            project: mappedProject
        )
        assertTargetExistsWithDerivedInfoPlist(
            named: "B-Info.plist",
            project: mappedProject
        )
    }

    // MARK: - Helpers

    private func assertSideEffectsCreateDerivedInfoPlist(
        named: String,
        content: [String: String],
        projectPath: AbsolutePath,
        sideEffects: [SideEffectDescriptor]
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: content,
            format: .xml,
            options: 0
        )

        #expect(sideEffects.first(where: { sideEffect in
            guard case let SideEffectDescriptor.file(file) = sideEffect else { return false }
            return file.path == projectPath
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named) && file.contents == data
        }) != nil)
    }

    private func assertTargetExistsWithDerivedInfoPlist(
        named: String,
        project: Project
    ) {
        #expect(project.targets.values.first(where: { (target: Target) in
            target.infoPlist?.path == project.path
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named)
        }) != nil)
    }
}
