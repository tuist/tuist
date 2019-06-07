// Reference: https://developer.apple.com/legacy/library/documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html#//apple_ref/doc/uid/TP40003931-CH3-SW105

import Basic
import Foundation
import TuistCore

class XcodeBuild {
    public enum Action: String {
        case archive
        case install
        case build
        case clean
        case installhdrs
        case installsrc
    }

    enum EnvironmentError: FatalError {
        case missingVariable(String)

        var type: ErrorType {
            return .abort
        }

        var description: String {
            switch self {
            case let .missingVariable(value):
                return "The build variable \(value) is missing."
            }
        }
    }

    class Environment {
        public let configuration: String
        public let frameworksFolderPath: String
        public let builtProductsDir: String
        public let targetBuildDir: String
        public let validArchs: [String]
        public let srcRoot: String
        public let action: Action
        public let codeSigningIdentity: String?

        public init(configuration: String,
                    frameworksFolderPath: String,
                    builtProductsDir: String,
                    targetBuildDir: String,
                    validArchs: [String],
                    srcRoot: String,
                    action: Action,
                    codeSigningIdentity: String?) {
            self.configuration = configuration
            self.frameworksFolderPath = frameworksFolderPath
            self.builtProductsDir = builtProductsDir
            self.targetBuildDir = targetBuildDir
            self.validArchs = validArchs
            self.srcRoot = srcRoot
            self.action = action
            self.codeSigningIdentity = codeSigningIdentity
        }

        public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
            guard let configuration = environment["CONFIGURATION"] else {
                throw EnvironmentError.missingVariable("CONFIGURATION")
            }
            guard let frameworksFolderPath = environment["FRAMEWORKS_FOLDER_PATH"] else {
                throw EnvironmentError.missingVariable("FRAMEWORKS_FOLDER_PATH")
            }
            guard let builtProductsDir = environment["BUILT_PRODUCTS_DIR"] else {
                throw EnvironmentError.missingVariable("BUILT_PRODUCTS_DIR")
            }
            guard let targetBuildDir = environment["TARGET_BUILD_DIR"] else {
                throw EnvironmentError.missingVariable("TARGET_BUILD_DIR")
            }
            guard let validArchs = environment["VALID_ARCHS"] else {
                throw EnvironmentError.missingVariable("VALID_ARCHS")
            }
            guard let srcRoot = environment["SRCROOT"] else {
                throw EnvironmentError.missingVariable("SRCROOT")
            }
            guard let action = environment["ACTION"] else {
                throw EnvironmentError.missingVariable("ACTION")
            }
            self.configuration = configuration
            self.frameworksFolderPath = frameworksFolderPath
            self.builtProductsDir = builtProductsDir
            self.targetBuildDir = targetBuildDir
            self.validArchs = validArchs.components(separatedBy: " ")
            self.srcRoot = srcRoot
            self.action = Action(rawValue: action) ?? .install
            self.codeSigningIdentity = environment["CODE_SIGN_IDENTITY"]
        }

        // MARK: - Public

        public func destinationPath() -> AbsolutePath {
            if action == .install {
                return AbsolutePath(builtProductsDir)
            } else {
                return AbsolutePath(targetBuildDir)
            }
        }

        private func frameworksPath() -> AbsolutePath {
            return destinationPath().appending(RelativePath(frameworksFolderPath))
        }
    }
}
