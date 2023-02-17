import Foundation

extension BuildRule {
    public enum FileType: Codable {
        case instrumentsPackageDefinition
        case metalAIR
        case machO
        case machOObject
        case siriKitIntent
        case coreMLMachineLearning
        case rcProjectDocument
        case skyboxDocument
        case interfaceBuilderStoryboard
        case interfaceBuilder
        case documentationCatalog
        case coreMLMachineLearningModelPackage
        case assemblyAsm
        case assemblyAsmAsm
        case llvmAssembly
        case cSource
        case clipsSource
        case cppSource
        case dtraceSource
        case dylanSource
        case fortranSource
        case glslSource
        case iigSource
        case javaSource
        case lexSource
        case metalShaderSource
        case migSource
        case nasmAssembly
        case openCLSource
        case pascalSource
        case protobufSource
        case rezSource
        case swiftSource
        case yaccSource
        case localizationString
        case localizationStringDictionary
        case xcAppExtensionPoints
        case xcodeSpecificationPlist
        case dae
        case nib
        case interfaceBuilderStoryboardPackage
        case classModel
        case dataModel
        case dataModelVersion
        case mappingModel
        case sourceFilesWithNamesMatching
    }
}
