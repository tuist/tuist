import Foundation

public enum CASOperation: Equatable {
    case download
    case upload
}

public enum CASOutputType: String, Equatable {
    case swift
    case sil
    case sib
    case image
    case object
    case dSYM
    case dependencies
    case autolink
    case swiftModule = "swiftmodule"
    case swiftDocumentation = "swiftdoc"
    case swiftInterface = "swiftinterface"
    case privateSwiftInterface = "private-swiftinterface"
    case packageSwiftInterface = "package-swiftinterface"
    case swiftSourceInfoFile = "swiftsourceinfo"
    case swiftConstValues = "const-values"
    case assembly = "s"
    case rawSil = "raw-sil"
    case rawSib = "raw-sib"
    case rawLlvmIr = "raw-llvm-ir"
    case llvmIR = "llvm-ir"
    case llvmBitcode = "llvm-bc"
    case diagnostics
    case emitModuleDiagnostics = "emit-module-diagnostics"
    case dependencyScanDiagnostics = "dependency-scan-diagnostics"
    case emitModuleDependencies = "emit-module.d"
    case objcHeader = "objc-header"
    case swiftDeps = "swift-dependencies"
    case modDepCache = "dependency-scanner-cache"
    case remap
    case importedModules = "imported-modules"
    case tbd
    case jsonDependencies = "json-dependencies"
    case jsonTargetInfo = "json-target-info"
    case jsonCompilerFeatures = "json-supported-features"
    case jsonSupportedFeatures = "json-supported-swift-features"
    case jsonSwiftArtifacts = "json-module-artifacts"
    case moduleTrace = "module-trace"
    case indexData = "index-data"
    case indexUnitOutputPath = "index-unit-output-path"
    case yamlOptimizationRecord = "yaml-opt-record"
    case bitstreamOptimizationRecord = "bitstream-opt-record"
    case pcm
    case pch
    case clangModuleMap = "modulemap"
    case jsonAPIBaseline = "api-baseline-json"
    case jsonABIBaseline = "abi-baseline-json"
    case jsonAPIDescriptor = "api-descriptor-json"
    case moduleSummary = "swift-module-summary"
    case moduleSemanticInfo = "module-semantic-info"
    case cachedDiagnostics = "cached-diagnostics"
    case localizationStrings = "localization-strings"
    case clangHeader = "clang-header"
}

public struct CASOutput: Equatable {
    public let nodeID: String
    public let checksum: String
    public let size: Int
    public let duration: TimeInterval
    public let compressedSize: Int
    public let operation: CASOperation
    public let type: CASOutputType

    public init(
        nodeID: String,
        checksum: String,
        size: Int,
        duration: TimeInterval,
        compressedSize: Int,
        operation: CASOperation,
        type: CASOutputType
    ) {
        self.nodeID = nodeID
        self.checksum = checksum
        self.size = size
        self.duration = duration
        self.compressedSize = compressedSize
        self.operation = operation
        self.type = type
    }
}
