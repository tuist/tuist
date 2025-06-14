# Application with Executable Non Local Dependencies

This example consists of two projects:
- Main app project, which contains the main iOS application
- Helper targets project, which includes various targets that the main app relies on

It demonstrates a scenario where the main app depends on executable targets from another project.
There are three such targets:
1. `AppExtension` - an app extension target
2. `WatchApp` - a watchOS app target
3. `TestHost` - an app target intended to serve as the test host for test targets (and also exemplifies a regular app target)
