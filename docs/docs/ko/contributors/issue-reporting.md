---
title: Issue reporting
titleTemplate: ':title - Contribute to Tuist'
description: Learn how to contribute to Tuist by reporting bugs
---

# Issue reporting

As user of Tuist, you might come across bugs or unexpected behaviors. 
If you do, we encourage you to report them so that we can fix them.

## GitHub issues is our ticketing platform

Issues should be reported on GitHub as [GitHub issues](https://github.com/tuist/tuist/issues) and not on Slack or other platforms. GitHub is better for tracing and managing issues, is closer to the codebase, and allows us to track the progress of the issue. Moreover, it encourages a long-form description of the problem, which forces the reporter to think about the problem and provide more context.

## Context is crucial

An issue without enough context will be deemed incomplete and the author will be asked for additional context. If not provided, the issue will be closed. Think about it this way: the more context you provide, the easier it is for us to understand the problem and fix it. So if you want your issue to be fixed, provide as much context as possible. Try to answer the following questions:

- What were you trying to do?
- How does your graph look?
- What version of Tuist are you using?
- Is this blocking you?

We also require you to provide a minimal **reproducible project**.

## Reproducible project

### What is a reproducible project?

A reproducible project is a small Tuist project to demonstrate a problem - often this problem is caused by a bug in Tuist. Your reproducible project should contain the bare minimum features needed to clearly demonstrate the bug.

### Why should you create a reproducible test case?

A reproducible projects lets us isolate the cause of a problem, which is the first step towards fixing it! The most important part of any bug report is to describe the exact steps needed to reproduce the bug.

A reproducible project is a great way to share a specific environment that causes a bug. Your reproducible project is the best way to help people that want to help you.

### Steps to create a reproducible project

- Create a new git repository.
- Initialize a project using `tuist init` in the repository directory.
- Add the code needed to recreate the error you’ve seen.
- Publish the code (your GitHub account is a good place to do this) and then link to it when creating an issue.

### Benefits of reproducible projects

- **Smaller surface area:** By removing everything but the error, you don’t have to dig to find the bug.
- **No need to publish secret code:** You might not be able to publish your main site (for many reasons). Remaking a small part of it as a reproducible test case allows you to publicly demonstrate a problem without exposing any secret code.
- **Proof of the bug:** Sometimes a bug is caused by some combination of settings on your machine. A reproducible test case allows contributors to pull down your build and test it on their machines as well. This helps verify and narrow down the cause of a problem.
- **Get help with fixing your bug:** If someone else can reproduce your problem, they often have a good chance of fixing the problem. It’s almost impossible to fix a bug without first being able to reproduce it.