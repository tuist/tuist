import Foundation
import XCLogParser

public enum XCActivityStepType: Hashable, Equatable {
    /// clang compilation step
    case cCompilation

    /// swift compilation step
    case swiftCompilation

    /// Build phase shell script execution
    case scriptExecution

    /// Libtool was used to create a static library
    case createStaticLibrary

    /// Linking of a library
    case linker

    /// Swift Runtime was copied
    case copySwiftLibs

    /// Asset's catalog compilation
    case compileAssetsCatalog

    /// Storyboard compilation
    case compileStoryboard

    /// Auxiliary file
    case writeAuxiliaryFile

    /// Storyboard linked
    case linkStoryboards

    /// Resource file was copied
    case copyResourceFile

    /// Swift Module was merged
    case mergeSwiftModule

    /// Xib file compilation
    case XIBCompilation

    /// With xcodebuild, swift files compilation appear aggregated
    case swiftAggregatedCompilation

    /// Precompile Bridging header
    case precompileBridgingHeader

    /// Non categorized step
    case other

    /// Validate watch, extensions binaries
    case validateEmbeddedBinary

    /// Validate app
    case validate

    init(signature: String) {
        // We check manually for SwiftCompile as XCLogParser doesn't currently support due to memory issues when exporting the
        // output as a JSON (which we don't do): https://github.com/MobileNativeFoundation/XCLogParser/issues/201
        if signature.hasPrefix("SwiftCompile") {
            self = .swiftCompilation
            return
        }
        switch DetailStepType.getDetailType(signature: signature) {
        case .cCompilation:
            self = .cCompilation
        case .swiftCompilation:
            self = .swiftCompilation
        case .scriptExecution:
            self = .scriptExecution
        case .createStaticLibrary:
            self = .createStaticLibrary
        case .linker:
            self = .linker
        case .copySwiftLibs:
            self = .copySwiftLibs
        case .compileAssetsCatalog:
            self = .compileAssetsCatalog
        case .compileStoryboard:
            self = .compileStoryboard
        case .writeAuxiliaryFile:
            self = .writeAuxiliaryFile
        case .linkStoryboards:
            self = .linkStoryboards
        case .copyResourceFile:
            self = .copyResourceFile
        case .mergeSwiftModule:
            self = .mergeSwiftModule
        case .XIBCompilation:
            self = .XIBCompilation
        case .swiftAggregatedCompilation:
            self = .swiftAggregatedCompilation
        case .precompileBridgingHeader:
            self = .precompileBridgingHeader
        case .validateEmbeddedBinary:
            self = .validateEmbeddedBinary
        case .validate:
            self = .validate
        case .none, .other:
            self = .other
        }
    }
}
