import Foundation
import TSCBasic
import TuistSupport

/// Side Effect Descriptor
///
/// Describes a side effect that needs to take place without performing it
/// immediately within a component. This allows components to be side effect free,
/// determenistic and much easier to test.
///
/// When part of a `ProjectDescriptor` or `WorkspaceDescriptor`, it
/// can be used in conjunction with `XcodeProjWriter` to perform side effects.
///
/// - seealso: `ProjectDescriptor`
/// - seealso: `WorkspaceDescriptor`
/// - seealso: `XcodeProjWriter`
public enum SideEffectDescriptor: Equatable {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Perform a command
    case command(CommandDescriptor)
}

//protocol SideEffectDescriptor: Equatable {
//    func run() throws
//}
//
//enum SigningEffectDescriptor: SideEffectDescriptor {
//    case signMe()
//    
//    func run() throws {
//        switch self {
//        case .signMe:
//            // Sign me
//            fatalError()
//        }
//    }
//}

//public struct SideEffect {
//    let run: () throws -> Void
//}
//
//public extension SideEffect {
//    static func createFile(at path: AbsolutePath, contents: String?) -> SideEffect {
//        .init() {
//            try FileHandler.shared.createFolder(path.parentDirectory)
//            if let contents = contents {
//                try contents.write(to: path.url, atomically: true, encoding: .utf8)
//            } else {
//                try FileHandler.shared.touch(path)
//            }
//        }
//    }
//    
//    static func command(_ arguments: String...) -> SideEffect {
//        .init() {
//            try System.shared.run(arguments)
//        }
//    }
//}
