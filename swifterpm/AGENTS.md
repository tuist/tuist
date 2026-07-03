# Repository Instructions

- When posting comments or reviews on GitHub pull requests, do not use em dashes.
- Write GitHub pull request comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly asked to do so.
- For local reviews, use `swifterpm/.blick/skills/swifterpm-swift-review/SKILL.md` as the project-specific review context.
- Use the shared `fileSystem` instance from `tuist/FileSystem` for filesystem operations. Convert URLs to `AbsolutePath` via the in-module `URL.absolutePath` helper. Do not use `Foundation.FileManager` in repository code, and do not call NIOFileSystem or `swift-tools-support-core` filesystem primitives directly.
