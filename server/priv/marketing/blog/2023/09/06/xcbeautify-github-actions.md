---
title: "XCBeautify: Supporting GitHub Actions Annotations"
category: "product"
tags: ['xcbeautify', 'GitHub Actions', 'Developer tools', 'DevOps', 'Open Source']
excerpt: "Learn about the latest xcbeautify renderer."
author: cpisciotta
---

# Overview

[XCBeautify](https://github.com/tuist/xcbeautify) now features an output format option for GitHub Actions.

# Getting Started

To utilize this function, simply run `xcbeautify` and add the `--renderer github-actions` flag during execution.

```sh
xcodebuild [flags] | xcbeautify --renderer github-actions
```

# How It Works

When you use the GitHub Actions renderer, xcbeautify formats output that harnesses [workflow commands](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions) to highlight warnings, errors, and other results directly within the GitHub user interface.

When you run a pull request check with the GitHub Actions renderer, you'll find all xcodebuild results and feedback in the `Annotations` section of the run summary.

![An image that shows a GitHub Actions run summary with xcbeautify comments.](/marketing/images/blog/2023/09/06/xcbeautify-gh-summary.png)

Furthermore, you'll find native inline feedback on PRs. This includes compiler warnings, compiler errors, and test failures.

![An image that shows a GitHub Actions run with an inline xcbeautify comment.](/marketing/images/blog/2023/09/06/xcbeautify-gh-comment.png)

By using this feature, you may avoid the need for additional third-party tools, such as [Danger](https://github.com/danger/swift) and related dependencies, to report a summary of xcodebuild output.

# Introducing Renderers

As of [0.21.0](https://github.com/tuist/xcbeautify/releases/tag/0.21.0), xcbeautify adds the `Renderer` concept. `Renderer` specifies the way you want xcbeautify to format its output.

Historically, xcbeautify has only supported one command line output format. This is now the format provided by the `TerminalRenderer`, and it's the default option.

`Renderer` provides the groundwork to add other output formats, such as for other CI/CD providers.

# Final Thoughts

If you'd like to learn more about this change, you can find the introductory pull request [here](https://github.com/tuist/xcbeautify/pull/107).

Thank you to [Eli Perkins](https://eliperkins.com) for providing support and direction on this change and supporting GitHub Actions annotations.

# Feedback

If you'd like to provide feedback or a contribution, please consider opening an [issue](https://github.com/tuist/xcbeautify/issues) or [pull request](https://github.com/tuist/xcbeautify/pulls).
