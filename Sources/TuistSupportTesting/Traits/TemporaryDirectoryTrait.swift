import Testing
import ServiceContextModule
import Path
import FileSystem
import Foundation

private enum TemporaryDirectoryTraitContextKey: ServiceContextKey {
    typealias Value = AbsolutePath
}

extension ServiceContext {
    public var temporaryDirectory: AbsolutePath! {
        get {
            self[TemporaryDirectoryTraitContextKey.self]
        } set {
            self[TemporaryDirectoryTraitContextKey.self] = newValue
        }
    }
}

public struct TemporaryDirectoryTrait: TestTrait, SuiteTrait, TestScoping {
  public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
      try await FileSystem().runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
          var serviceContext = ServiceContext.current ?? ServiceContext.topLevel
          serviceContext.temporaryDirectory = temporaryDirectory
          try await ServiceContext.withValue(serviceContext) {
              try await function()
          }
      }
  }
}

public extension Trait where Self == TemporaryDirectoryTrait {
    static var temporaryDirectory: Self { Self() }
}
