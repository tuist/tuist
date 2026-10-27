# TuistCI

- CI detection is purely environment-variable based.
- Keep this module cross-platform. Cargo reporting and compile-once sharding use it on Linux as well as macOS, so its SwiftPM target belongs in the shared target list.
