# iOS app with transitive framework through macro executable

This fixture contains an iOS app that transitively and directly depends on a Swift Macro (executable)'s direct dependency.
It was included [in this issue](https://github.com/tuist/tuist/issues/5988) because the set up caused the warming of the binary cache to fail due to "multiple commands produce the same output" error when archiving.
As a solution, we moved away from using archive, and instead use the build action to warm the cache.