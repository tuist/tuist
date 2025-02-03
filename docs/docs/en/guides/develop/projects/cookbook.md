---
title: Cookbook
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Learn some useful recipes for working with Tuist and Xcode projects.
---

# Cookbook {#cookbook}

Here we are sharing a few recipes that you might find useful when working with Tuist and Xcode projects.

## Generate a list with all your project dependencies {#generate-a-list-with-all-your-project-dependencies}

To comply with the license of your open source dependencies (e.g. MIT-licensed),
you might need to include a list of all the dependencies you use in your project.
Tuist doesn't have a built-in command for that, but you can use [swift-package-list](https://github.com/FelixHerrmann/swift-package-list) for that:

```bash
mise x spm:FelixHerrmann/swift-package-list -- \
    swift-package-list Package.swift \
    --custom-source-packages-path .build \
    --output-type plist \
    --output-path Sources/Core
```

> [!TIP]
> You can use `--output-path` to output it in a directory that contains the resources of the target from where the file will be read at runtime.
