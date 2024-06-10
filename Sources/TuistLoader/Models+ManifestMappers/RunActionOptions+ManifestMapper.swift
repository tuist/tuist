import Foundation
import Path
import ProjectDescription
import XcodeGraph

extension XcodeGraph.RunActionOptions {
    /// Maps a ProjectDescription.RunActionOptions instance into a XcodeGraph.RunActionOptions instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the options.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunActionOptions,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.RunActionOptions {
        var language: String?
        var storeKitConfigurationPath: AbsolutePath?
        var simulatedLocation: XcodeGraph.SimulatedLocation?
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

        return XcodeGraph.RunActionOptions(
            language: language,
            region: manifest.region,
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation,
            enableGPUFrameCaptureMode: enableGPUFrameCaptureMode
        )
    }
}
