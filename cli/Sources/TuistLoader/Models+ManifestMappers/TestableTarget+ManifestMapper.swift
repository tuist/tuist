import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.TestableTarget {
    /// Maps a ProjectDescription.TestableTarget instance into a XcodeGraph.TestableTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of testable target model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TestableTarget,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.TestableTarget {
        let target = XcodeGraph.TargetReference(
            projectPath: try generatorPaths.resolveSchemeActionProjectPath(manifest.target.projectPath),
            name: manifest.target.targetName
        )

        var simulatedLocation: XcodeGraph.SimulatedLocation?

        if let manifestLocation = manifest.simulatedLocation {
            switch (manifestLocation.identifier, manifestLocation.gpxFile) {
            case let (identifier?, .none):
                simulatedLocation = .reference(identifier)
            case let (.none, gpxFile?):
                simulatedLocation = .gpxFile(try generatorPaths.resolveSchemeActionProjectPath(gpxFile))
            default:
                break
            }
        }

        let parallelization: XcodeGraph.TestableTarget.Parallelization = switch manifest.parallelization {
        case .disabled: .none
        case .swiftTestingOnly: .swiftTestingOnly
        case .enabled: .all
        }

        return TestableTarget(
            target: target,
            skipped: manifest.isSkipped,
            parallelization: parallelization,
            randomExecutionOrdering: manifest.isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation,
            selectedTags: normalizedTags(manifest.selectedTags),
            skippedTags: normalizedTags(manifest.skippedTags)
        )
    }

    /// Normalizes user-provided Swift Testing tag names into the spelling Xcode writes into
    /// `.xctestplan` files, which is the Swift symbol spelling with its leading dot (`".contract"`).
    /// A name that already contains a dot anywhere is passed through untouched, so a fully qualified
    /// spelling such as `"Tag.contract"` is not mangled into `".Tag.contract"`. Whitespace is trimmed,
    /// empty names are dropped, and order is preserved without deduplication.
    private static func normalizedTags(_ tags: [String]) -> [String] {
        tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.contains(".") ? trimmed : ".\(trimmed)"
        }
    }
}
