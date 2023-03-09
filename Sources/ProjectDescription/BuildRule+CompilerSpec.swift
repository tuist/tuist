import Foundation

extension BuildRule {
    /// The type of compiler spec which is used for a selected file type.
    /// All the values are taken from build rule options hidden under a pup-up button's menu next to a label `Using` in a target's `Build Rules` section.
    public enum CompilerSpec: Codable {
        case appIntentsMetadataExtractor
        case appShortcutStringsMetadataExtractor
        case appleClang
        case assetCatalogCompiler
        case codeSign
        case compileRealityComposerProject
        case compileSceneKitShaders
        case compileSkybox
        case compileUSDZ
        case compressPNG
        case copyPlistFile
        case copySceneKitAssets
        case copyStringsFile
        case copyTiffFile
        case coreDataMappingModelCompiler
        case coreMLModelCompiler
        case dataModelCompiler
        case defaultCompiler
        case dTrace
        case generateSpriteKitTextureAtlas
        case iconutil
        case instrumetsPackageBuilder
        case intentDefinitionCompiler
        case interfaceBuilderNIBPostprocessor
        case interfaceBuilderStoryboardCompiler
        case interfaceBuilderStoryboardLinker
        case interfaceBuilderStoryboardPostprocessor
        case interfaceBuilderXIBCompiler
        case ioKitInterfaceGenerator
        case lex
        case lsRegisterURL
        case metalCompiler
        case metalLinker
        case mig
        case nasm
        case nmedit
        case openCL
        case osaCompile
        case pbxcp
        case processSceneKitDocument
        case processXCAppExtensionPoints
        case rez
        case stripSymbols
        case swiftCompiler
        case swiftABIBaselineGenerator
        case swiftFrameworkABIChecker
        case textBasedAPITool
        case unifdef
        case yacc
        case customScript
    }
}
