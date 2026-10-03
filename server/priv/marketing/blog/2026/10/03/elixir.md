---
title: "Tuist for Elixir"
category: "product"
tags: ["elixir", "mix", "build-insights", "test-insights", "flaky-tests", "test-sharding"]
excerpt: ""
author: pepicrft
---

We've been fans of Elixir at Tuist for a long time. José Valim built something remarkable on top of the Erlang VM, and it's a big part of why a team our size can move fast and scale with ease. We've long wanted to give something back to the ecosystem that gave us so much. The itch was always there, but building our compute and global cache infrastructure had to come first. Now that we finally have the space, this is the love letter we've been wanting to write.

To us, Mix is a build system like Xcode, Gradle, and Bazel. Each has its own conventions, but underneath they share the same shape: a graph of work, tasks like compilation that take time, test suites made of test cases, and telemetry that tells you where the time went. Our vision is to meet teams where they are. Companies should be free to choose the build system that works best for them, and Tuist should plug into the capabilities it already offers instead of pushing everyone onto a single one. Elixir was the natural next step on that path, with one more reason to take it: the Tuist server is written in Elixir. We can use it on our own code every day and keep refining the experience until it's the support we'd want ourselves.

## Keep typing mix test

<!-- The tuist_ex Hex package. Alias test and compile to its tasks and nothing else changes for people or coding agents. -->

## Where a build spends its time

<!-- Build insights: compile time per file, the dependency graph (compile-time dependencies and dependents), the timeline, machine metrics. How the graph points at the files that serialize a build and keep it from using every core. -->

## Tests you can trust

<!-- Test insights and flaky tests: retries with test_retries, cross-run detection on the same commit, the Flaky Tests page and automations. -->

## Compile once, test everywhere

<!-- Test sharding: mix tuist.test.build plans shards from historical timings, uploads the build, and every shard runs without compiling. -->

## Try it

<!-- Link to the Elixir guide: https://tuist.dev/en/docs/guides/get-started/elixir-project -->
