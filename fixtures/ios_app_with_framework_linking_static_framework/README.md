# iOS app with a dynamic framework that links a static framework


An example project demonstrating an iOS application linking a dynamic framework which itself depends on a static framework with transitive static dependencies.

Only `Framework1.framework` should be linked and included into App, everything else should be statically linked into the Framework1 executable.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
    - Framework1Tests (iOS unit tests)
  - Framework2:
    - Framework2 (static iOS framework)
    - Framework2Tests (iOS unit tests)
  - Framework3:
    - Framework3 (static iOS framework)
    - Framework3Tests (iOS unit tests)
  - Framework4:
    - Framework4 (static iOS framework)
    - Framework4Tests (iOS unit tests)
```

Dependencies:

- App -> Framework1
- Framework1 -> Framework2
- Framework1 -> Framework3
- Framework3 -> Framework4


