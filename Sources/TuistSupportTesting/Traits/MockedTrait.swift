import Testing
import ServiceContextModule
import Path
import FileSystem
import Foundation

public struct MockedTrait: TestTrait, SuiteTrait, TestScoping {
  public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
      try await ServiceContext.withTestingDependencies(function)
  }
}

public extension Trait where Self == MockedTrait {
static var mocked: Self { Self() }
}
