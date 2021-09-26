---
title: Run tasks
slug: '/commands/task'
description: 'Learn how to to automate arbitrary tasks with tuist in Swift.'
---

### Context

When we write apps, it is often necessary to write some supporting code for e.g. releasing, downloading localizations, etc.
These are often written in Shell or Ruby which only a handful of developers on your team might be familiar with.
This means that these files are edited by an exclusive group and they are sort of "magical" for others.
We try to fix that by introducing a concept of "Tasks" where you can define custom commands - in Swift!

### Defining a task

You can prepend any executable with `tuist-` and add it to your `PATH`. If you for example add `tuist-my-command` to your `PATH`, you will be able to run `tuist my-command` and `tuist-my-command` will automatically be executed.