import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.TestAction {
    // swiftlint:disable function_body_length
    /// Maps a ProjectDescription.TestAction instance into a TuistGraph.TestAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of test action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TestAction, generatorPaths: GeneratorPaths) throws -> TuistGraph.TestAction {
        // swiftlint:enable function_body_length
        let testPlans: [TuistGraph.TestPlan]?
        let targets: [TuistGraph.TestableTarget]
        let arguments: TuistGraph.Arguments?
        let coverage: Bool
        let codeCoverageTargets: [TuistGraph.TargetReference]
        let expandVariablesFromTarget: TuistGraph.TargetReference?
        let diagnosticsOptions: Set<TuistGraph.SchemeDiagnosticsOption>
        let language: SchemeLanguage?
        let region: String?

        if let plans = manifest.testPlans {
            testPlans = try plans.enumerated().map { index, path in
                try TestPlan(path: generatorPaths.resolve(path: path), isDefault: index == 0, generatorPaths: generatorPaths)
            }

            // not used when using test plans
            targets = []
            arguments = nil
            coverage = false
            codeCoverageTargets = []
            expandVariablesFromTarget = nil
            diagnosticsOptions = []
            language = nil
            region = nil
        } else {
            targets = try manifest.targets
                .map { try TuistGraph.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
            arguments = manifest.arguments.map { TuistGraph.Arguments.from(manifest: $0) }
            coverage = manifest.options.coverage
            codeCoverageTargets = try manifest.options.codeCoverageTargets.map {
                TuistGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
                TuistGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }

            diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistGraph.SchemeDiagnosticsOption.from(manifest: $0) })
            language = manifest.options.language
            region = manifest.options.region

            // not used when using targets
            testPlans = nil
        }

        let configurationName = manifest.configuration.rawValue
        let preActions = try manifest.preActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }

        return TestAction(
            targets: targets,
            arguments: arguments,
            configurationName: configurationName,
            attachDebugger: manifest.attachDebugger,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            expandVariableFromTarget: expandVariablesFromTarget,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: diagnosticsOptions,
            language: language?.identifier,
            region: region,
            testPlans: testPlans
        )
    }
}

extension TestPlan {
     init(path: AbsolutePath, isDefault: Bool, generatorPaths: GeneratorPaths) throws {
        let jsonDecoder = JSONDecoder()
        let testPlanData = try Data(contentsOf: path.asURL)
        let xcTestPlan = try jsonDecoder.decode(XCTestPlan.self, from: testPlanData)

        try self.init(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                try TestTarget(
                    target: TargetReference(
                        projectPath: generatorPaths.resolve(path: .relativeToRoot(testTarget.target.projectPath)).removingLastComponent(),
                        name: testTarget.target.name
                    ),
                    isEnabled: testTarget.enabled
                )
            },
            isDefault: isDefault
        )
    }
}

private struct XCTestPlan: Decodable {
    struct Target: Decodable {
        let projectPath: String
        let name: String

        enum CodingKeys: CodingKey {
            case containerPath
            case name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let containerPath = try container.decode(String.self, forKey: .containerPath)
            let containerInfo = containerPath.split(separator: ":")
            switch containerInfo.count {
            case 1:
                projectPath = containerPath
            case 2 where containerInfo[0] == "container":
                projectPath = String(containerInfo[1])
            default:
                throw DecodingError.valueNotFound(
                    String.self,
                    .init(codingPath: container.codingPath, debugDescription: "Invalid containerPath")
                )
            }
            name = try container.decode(String.self, forKey: .name)
        }
    }

    struct TestTarget: Decodable {
        let enabled: Bool
        let target: Target

        enum CodingKeys: CodingKey {
            case enabled
            case target
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            target = try container.decode(XCTestPlan.Target.self, forKey: .target)
        }
    }

    let testTargets: [TestTarget]
}
