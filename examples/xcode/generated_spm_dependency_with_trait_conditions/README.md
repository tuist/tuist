# SPM dependency with trait conditions

This example contains an app that depends on the [Apollo iOS](https://github.com/apollographql/apollo-ios) SDK. Apollo depends on [SQLite.swift](https://github.com/stephencelis/SQLite.swift), which has a trait-conditional dependency on SQLCipher. This fixture validates that Tuist correctly filters out dependencies whose trait conditions are not satisfied.
