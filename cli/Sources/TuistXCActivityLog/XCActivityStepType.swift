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

    init(stepTypeString: String) {
        switch stepTypeString {
        case "c_compilation": self = .cCompilation
        case "swift_compilation": self = .swiftCompilation
        case "script_execution": self = .scriptExecution
        case "create_static_library": self = .createStaticLibrary
        case "linker": self = .linker
        case "copy_swift_libs": self = .copySwiftLibs
        case "compile_assets_catalog": self = .compileAssetsCatalog
        case "compile_storyboard": self = .compileStoryboard
        case "write_auxiliary_file": self = .writeAuxiliaryFile
        case "link_storyboards": self = .linkStoryboards
        case "copy_resource_file": self = .copyResourceFile
        case "merge_swift_module": self = .mergeSwiftModule
        case "xib_compilation": self = .XIBCompilation
        case "swift_aggregated_compilation": self = .swiftAggregatedCompilation
        case "precompile_bridging_header": self = .precompileBridgingHeader
        case "validate_embedded_binary": self = .validateEmbeddedBinary
        case "validate": self = .validate
        default: self = .other
        }
    }

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
