import Foundation
import TSCBasic
import TuistGraph

public extension DependenciesGraph {
    /// A snapshot of `graph.json` file.
    static var testJson: String {
        """
        {
          "externalDependencies" : {
            "RxSwift" : {
              "kind" : "xcframework",
              "path" : "/Tuist/Dependencies/Carthage/RxSwift.xcframework",
              "architectures" : [
                "arm64_32",
                "x86_64",
                "armv7",
                "armv7k",
                "arm64",
                "i386"
              ]
            }
          }
        }
        """
    }

    static func test(externalDependencies: [String: ExternalDependency] = [:]) -> Self {
        return .init(externalDependencies: externalDependencies)
    }
}
