import Testing
import ServiceContextModule
import Path
import FileSystem
import Foundation

private enum TemporaryFixtureTraitServiceContextTrait: ServiceContextKey {
    typealias Value = AbsolutePath
}

extension ServiceContext {
    public var temporaryFixtureDirectory: AbsolutePath! {
        get {
            self[TemporaryFixtureTraitServiceContextTrait.self]
        } set {
            self[TemporaryFixtureTraitServiceContextTrait.self] = newValue
        }
    }
}

public struct TemporaryFixtureTrait: TestTrait, SuiteTrait, TestScoping {
    private let fixturePath: String
    
    init(fixturePath: String) {
        self.fixturePath = fixturePath
    }

  public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
      try await FileSystem().runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
          let path = try RelativePath(validating: fixturePath)
          let fixturePath = _fixturePath(path: path)
          let destinationPath = (temporaryDirectory).appending(component: path.basename)
          try await FileSystem().copy(fixturePath, to: destinationPath)
          var serviceContext = ServiceContext.current ?? ServiceContext.topLevel
          serviceContext.temporaryFixtureDirectory = destinationPath
          try await ServiceContext.withValue(serviceContext) {
              try await function()
          }
      }
  }
}

public extension Trait where Self == TemporaryFixtureTrait {
    static func temporaryFixture(_ fixturePath: String) -> Self {
        Self(fixturePath: fixturePath)
    }
}
