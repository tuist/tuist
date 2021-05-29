---
title: Reporting bugs
slug: /contributors/reporting-bugs
description: This documentation page contains guidelines for reporting bugs that are found while using Tuist.
---

This document contains simple guidelines that users can follow to report bugs found while using the tool.
One of the most important pieces of bug reports are reproducible cases because they help developers narrow down the issue for further investigation.

### Reproducible cases

#### What is a reproducible test case?

A reproducible test case is a small Tuist project to demonstrate a problem - often this problem is caused by a bug in Tuist. Your reproducible test case should contain the bare minimum features needed to clearly demonstrate the bug.

#### Why should you create a reproducible test case?

A reproducible test case lets you isolate the cause of a problem, which is the first step towards fixing it! The most important part of any bug report is to describe the exact steps needed to reproduce the bug.

A reproducible test case is a great way to share a specific environment that causes a bug. Your reproducible test case is the best way to help people that want to help you.

#### Steps to create a reproducible test case

- Create a new git repository.
- Initialize a project using `tuist init` in the repository directory.
- Add the code needed to recreate the error you’ve seen.
- Publish the code _(your GitHub account is a good place to do this)_ and then link to it when creating an issue.

#### Benefits of reproducible test cases

- **Smaller surface area:** By removing everything but the error, you don’t have to dig to find the bug.
- **No need to publish secret code:** You might not be able to publish your main site (for many reasons). Remaking a small part of it as a reproducible test case allows you to publicly demonstrate a problem without exposing any secret code.
- **Proof of the bug:** Sometimes a bug is caused by some combination of settings on your machine. A reproducible test case allows contributors to pull down your build and test it on their machines as well. This helps verify and narrow down the cause of a problem.
- **Get help with fixing your bug:** If someone else can reproduce your problem, they often have a good chance of fixing the problem. It’s almost impossible to fix a bug without first being able to reproduce it.
