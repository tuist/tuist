---
title: Generate documentation
slug: '/commands/documentation'
description: 'Learn how to generate documentation for your Xcode projects.'
---

When working in modular codebases, it might be useful to check out the documentation of the public API of a given module. For that reason, Tuist provides a command, tuist doc, that given a target, it generates its documentation and opens it on the browser. Under the hood, it uses [swift-doc](https://github.com/SwiftDocOrg/swift-doc).

```bash
tuist doc --path /path/to/Project.swift MyApp
```

### Arguments

| Argument | Short | Description                                                         | Default           | Required |
| -------- | ----- | ------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | Path to the project's directory where the Project.swift is located. | Current directory | No       |
