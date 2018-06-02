// Reference: https://github.com/Carthage/Carthage/blob/53da2e143306ba502e468842667ee8cd763d5a5b/Source/CarthageKit/Xcode.swift
// Reference: https://pspdfkit.com/guides/ios/current/faq/framework-size/#toc_dsym-and-bcsymbolmaps
// Reference: https://github.com/xcodeswift/xctools/blob/master/Sources/Frameworks/EmbedCommand.swift
import Basic
import Foundation

enum FrameworkEmbedderError: FatalError {
    case missingFramework
    case frameworkNotFound(AbsolutePath)
    case missingEnvironment

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingFramework:
            return .abort
        case .frameworkNotFound:
            return .abort
        case .missingEnvironment:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .missingFramework:
            return "A framework needs to be specified."
        case let .frameworkNotFound(path):
            return "Framework not found at path \(path.asString)."
        case .missingEnvironment:
            return "Running xpm-embed outside Xcode build phases is not allowed."
        }
    }
}

/// Embeds the input framework into the built product.
public class FrameworkEmbedder {
    /// Context.
    private let context: CommandsContexting

    /// Constructor
    public convenience init() {
        self.init(context: CommandsContext())
    }

    init(context: CommandsContexting) {
        self.context = context
    }

    /// Embeds the given framework into the built product.
    ///
    /// - Parameters:
    ///   - frameworkPath: relative path to the framework.
    ///   - environment: XcodeBuild environment.
    func embed(frameworkPath: RelativePath,
               environment: XcodeBuild.Environment) throws {
        let frameworksPath = RelativePath(environment.frameworksFolderPath)
        let builtProductsDir = AbsolutePath(environment.builtProductsDir)
        let validArchs = environment.validArchs
        let srcRoot = AbsolutePath(environment.srcRoot)
        let frameworkAbsolutePath = srcRoot.appending(frameworkPath)
        let frameworkDsymPath = AbsolutePath("\(frameworkPath.asString).dSYM")
        let productFrameworksPath = builtProductsDir.appending(frameworksPath)
        let action = environment.action

        // Conditions
        if !context.fileHandler.exists(frameworkAbsolutePath) {
            throw FrameworkEmbedderError.frameworkNotFound(frameworkAbsolutePath)
        }
        if try Embeddable(path: frameworkAbsolutePath).architectures().filter({ validArchs.contains($0) }).count == 0 {
            context.printer.print("Ignoring framework \(frameworkPath.asString). It does not support the current architecture")
        }

        if !context.fileHandler.exists(productFrameworksPath) {
            try context.fileHandler.createFolder(productFrameworksPath)
        }

        // Framework
        let frameworkOutputPath = productFrameworksPath.appending(component: frameworkAbsolutePath.components.last!)
        try context.fileHandler.copy(from: frameworkAbsolutePath,
                                     to: frameworkOutputPath)
        try Embeddable(path: frameworkOutputPath).strip(keepingArchitectures: validArchs)

        // Symbols
        if context.fileHandler.exists(frameworkDsymPath) {
            let frameworkDsymOutputPath = productFrameworksPath.appending(component: frameworkDsymPath.components.last!)
            try context.fileHandler.copy(from: frameworkDsymPath,
                                         to: frameworkDsymOutputPath)
            try Embeddable(path: frameworkDsymOutputPath).strip(keepingArchitectures: validArchs)
        }

        // A BCSymbolMap is a lot like a dSYM for bitcode.
        // Xcode builds it as part of creating the app binary, and also for every dynamic framework.
        // It's required for re-symbolicating function/method names to understand crashers.
        // Symbol maps are per architecture, so there are currently two (armv7 and arm64)

        // Install is also used when the app is being archived.
        if action == .install {
            try Embeddable(path: frameworkAbsolutePath).bcSymbolMapsForFramework().forEach { bcInputPath in
                let bcOutputPath = builtProductsDir.appending(component: bcInputPath.components.last!)
                if !context.fileHandler.exists(bcOutputPath.parentDirectory) {
                    try context.fileHandler.createFolder(bcOutputPath.parentDirectory)
                }
                if context.fileHandler.exists(bcOutputPath) {
                    try context.fileHandler.delete(bcOutputPath)
                }
                try context.fileHandler.copy(from: bcInputPath, to: bcOutputPath)
            }
        }
    }

    /// Embeds the passed framewok into the built product.
    public func embed() {
        do {
            if CommandLine.arguments.count < 2 {
                throw FrameworkEmbedderError.missingFramework
            }
            guard let environment = XcodeBuild.Environment() else {
                throw FrameworkEmbedderError.missingEnvironment
            }
            try embed(frameworkPath: RelativePath(CommandLine.arguments[1]),
                      environment: environment)
        } catch let error as FatalError {
            context.errorHandler.fatal(error: error)
        } catch {
            context.errorHandler.fatal(error: UnhandledError(error: error))
        }
    }
}
