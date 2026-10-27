The fixtures under `DependencyResolution/External` are copied from
`swiftlang/swift-package-manager/Fixtures/DependencyResolution/External`.

They cover resolver graph scenarios from SwiftPM's functional dependency
resolution tests:

- `Simple`: version selection for one external dependency.
- `Complex`: transitive source-control dependencies with relative package URLs.
- `Branch`: a branch-based source-control dependency.
- `PackageLookupCaseInsensitive`: a local path dependency whose product lookup
  differs in case from its package directory.

SwiftPM is distributed under the Apache License v2.0 with Runtime Library
Exception. These fixtures are kept here only as e2e parity coverage.
