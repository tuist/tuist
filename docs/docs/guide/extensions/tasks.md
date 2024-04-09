---
title: Tasks
description: Learn how to define tasks in your projects.
---

# Tasks

When we write apps, it is often necessary to write some supporting code for (e.g. releasing, downloading localizations, etc). These are often written in bash or [Ruby](https://www.ruby-lang.org/en/) which only a handful of developers on your team might be familiar with. This means that these files are edited by an exclusive group and they are sort of “magical” for others. We try to fix that by introducing a concept of tasks where you can define custom commands - in Swift!

> [!TIP] AUTO-LOADED TASKS
> Any `$PATH`-exposed executable that follows the `tuist-xxxx` is considered a task and can be invoked through `tuist xxxx`

## Creating a task

Every Swift file under the `Tuist/Tasks` directory is considered a task.