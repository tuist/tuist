// Per-test coverage evidence for Swift Testing.
//
// Copy this file into a test target and add `.coverageAttribution` to the suites (it applies to
// every test and nested suite inside) or to single tests:
//
//     @Suite(.coverageAttribution) struct CheckoutTests { ... }
//
// XCTest needs nothing: Tuist observes it from outside. Swift Testing has no hook an injected
// library can join, so this trait tells Tuist's coverage observer where each test starts and
// ends. The observer is looked up at run time: when Tuist did not inject it (Xcode, a plain
// `xcodebuild test`, or a run that collects no evidence) the trait does nothing.
//
// Evidence per test needs the tests of a process to run one at a time: a test that overlaps
// another is left out. Tuist's generated schemes already run serially; otherwise use
// `.serialized` on the suite or `-parallel-testing-enabled NO`.
import Testing

#if canImport(Darwin)
    import Darwin

    private typealias CoverageScope = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void

    private func coverageObserverFunction(_ name: String) -> CoverageScope? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(symbol, to: CoverageScope.self)
    }

    private let coverageScopeBegin = coverageObserverFunction("tuist_coverage_scope_begin")
    private let coverageScopeEnd = coverageObserverFunction("tuist_coverage_scope_end")
#endif

struct CoverageAttributionTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        #if canImport(Darwin)
            guard let coverageScopeBegin, let coverageScopeEnd, testCase != nil else {
                try await function()
                return
            }
            let components = test.id.nameComponents
            let module = test.id.moduleName
            let suite = components.count >= 2 ? components[components.count - 2] : ""
            let name = components.last ?? test.name
            coverageScopeBegin(module, suite, name)
            defer { coverageScopeEnd(module, suite, name) }
            try await function()
        #else
            try await function()
        #endif
    }
}

extension Trait where Self == CoverageAttributionTrait {
    static var coverageAttribution: Self { Self() }
}
