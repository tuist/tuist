import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.BuildRule.FileType {
    // swiftlint:disable function_body_length
    static func from(
        manifest: ProjectDescription.BuildRule.FileType
    ) -> XcodeGraph.BuildRule.FileType {
        switch manifest {
        case .instrumentsPackageDefinition:
            return .instrumentsPackageDefinition
        case .metalAIR:
            return .metalAIR
        case .machO:
            return .machO
        case .machOObject:
            return .machOObject
        case .siriKitIntent:
            return .siriKitIntent
        case .coreMLMachineLearning:
            return .coreMLMachineLearning
        case .rcProjectDocument:
            return .rcProjectDocument
        case .skyboxDocument:
            return .skyboxDocument
        case .interfaceBuilderStoryboard:
            return .interfaceBuilderStoryboard
        case .interfaceBuilder:
            return .interfaceBuilder
        case .documentationCatalog:
            return .documentationCatalog
        case .coreMLMachineLearningModelPackage:
            return .coreMLMachineLearningModelPackage
        case .assemblyAsm:
            return .assemblyAsm
        case .assemblyAsmAsm:
            return .assemblyAsmAsm
        case .llvmAssembly:
            return .llvmAssembly
        case .cSource:
            return .cSource
        case .clipsSource:
            return .clipsSource
        case .cppSource:
            return .cppSource
        case .dtraceSource:
            return .dtraceSource
        case .dylanSource:
            return .dylanSource
        case .fortranSource:
            return .fortranSource
        case .glslSource:
            return .glslSource
        case .iigSource:
            return .iigSource
        case .javaSource:
            return .javaSource
        case .lexSource:
            return .lexSource
        case .metalShaderSource:
            return .metalShaderSource
        case .migSource:
            return .migSource
        case .nasmAssembly:
            return .nasmAssembly
        case .openCLSource:
            return .openCLSource
        case .pascalSource:
            return .pascalSource
        case .protobufSource:
            return .protobufSource
        case .rezSource:
            return .rezSource
        case .swiftSource:
            return .swiftSource
        case .yaccSource:
            return .yaccSource
        case .localizationString:
            return .localizationString
        case .localizationStringDictionary:
            return .localizationStringDictionary
        case .xcAppExtensionPoints:
            return .xcAppExtensionPoints
        case .xcodeSpecificationPlist:
            return .xcodeSpecificationPlist
        case .dae:
            return .dae
        case .nib:
            return .nib
        case .interfaceBuilderStoryboardPackage:
            return .interfaceBuilderStoryboardPackage
        case .classModel:
            return .classModel
        case .dataModel:
            return .dataModel
        case .dataModelVersion:
            return .dataModelVersion
        case .mappingModel:
            return .mappingModel
        case .sourceFilesWithNamesMatching:
            return .sourceFilesWithNamesMatching
        }
    }
    // swiftlint:enable function_body_length
}
