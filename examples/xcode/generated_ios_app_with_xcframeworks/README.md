# iOS app with xcframeworks

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - MyFramework:
    - MyFramework (dynamic iOS framework)
  - MyStaticFramework:
    - MyStaticFramework (static iOS framework)
  - MyStaticLibirary:
    - MyStaticLibrary (static iOS libraries)
```

An example of an application which depends on prebuilt `.xcframework`s.

The `.xcframework` can be obtained by running the `build.sh` script within the each of the xcframework directories
e.g. `ios_app_with_xcframeworks/XCFrameworks/MyFramework/build.sh`.