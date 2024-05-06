# iOS app with frameworks


Slightly more complicated project that consists of an iOS app and few frameworks.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
    - Framework1Tests (iOS unit tests)
  - Framework2:
    - Framework2 (dynamic iOS framework)
    - Framework2Tests (iOS unit tests)
  - Framework3:
    - Framework3 (dynamic iOS framework)
  - Framework4:
    - Framework4 (dynamic iOS framework)
  - Framework5:
    - Framework5 (dynamic iOS framework)
```

Dependencies:

- App -> Framework1
- App -> Framework2
- Framework1 -> Framework2
- Framework2 -> Framework3
- Framework3 -> Framework4
- Framework4 -> Framework5