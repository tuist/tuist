# TuistRootDirectoryLocator

Preserve upward root detection and marker precedence within each directory: `Tuist/`, `Tuist.swift`, `tuist.toml`, `Plugin.swift`, then `.git/`. Only fall back to `Package.swift` at the starting directory when no root was found above it.
