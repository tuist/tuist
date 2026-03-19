# iOS app with a static framework using xcstrings

A workspace with an application that depends on a static framework containing `.xcstrings` string catalog resources. This fixture verifies that Xcode does not mark strings as stale during build when the static framework uses a companion resource bundle.

```
Workspace:
  - App:
    - App (iOS app)
  - StaticFramework:
    - StaticFramework (static iOS framework)
    - StaticFramework_StaticFramework (iOS bundle)
```

Dependencies:

- App -> StaticFramework
- StaticFramework -> StaticFramework_StaticFramework
