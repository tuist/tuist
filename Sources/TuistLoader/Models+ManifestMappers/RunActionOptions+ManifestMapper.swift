import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.RunActionOptions {
    /// Maps a ProjectDescription.RunActionOptions instance into a TuistGraph.RunActionOptions instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the options.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunActionOptions,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.RunActionOptions {
        var language: String?
        var storeKitConfigurationPath: AbsolutePath?
        var simulatedLocation: SimulatedLocation?
        var enableGPUFrameCaptureMode: GPUFrameCaptureMode

        language = manifest.language?.identifier

        switch manifest.enableGPUFrameCaptureMode {
        case .autoEnabled:
            enableGPUFrameCaptureMode = .autoEnabled
        case .metal:
            enableGPUFrameCaptureMode = .metal
        case .openGL:
            enableGPUFrameCaptureMode = .openGL
        case .disabled:
            enableGPUFrameCaptureMode = .disabled
        }

        if let path = manifest.storeKitConfigurationPath {
            storeKitConfigurationPath = try generatorPaths.resolveSchemeActionProjectPath(path)
        }

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

        return TuistGraph.RunActionOptions(
            language: language,
            region: manifest.region,
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation,
            enableGPUFrameCaptureMode: enableGPUFrameCaptureMode
        )
    }
}
