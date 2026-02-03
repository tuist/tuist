// Re-export MockEnvironment and related types from TuistEnvironment
// so that tests importing TuistTesting can continue to use them
@_exported import struct TuistEnvironment.EnvironmentTestingTrait
@_exported import class TuistEnvironment.MockEnvironment
@_exported import func TuistEnvironment.withMockedEnvironment
