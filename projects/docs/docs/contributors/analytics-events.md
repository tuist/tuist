---
title: Analytics events
slug: '/contributors/analytics-events'
description: The definition of the analytics events sent to tuist.stats.io
---

This document shows the list of all analytics events sent by Tuist.

### CommandEvent

A `CommandEvent` is sent every time a Tuist command successfully completes.
Schema:

| Parameter name        | Parameter type     | Parameter description                                        | Example                            | Required |
| --------------------- | ------------------ | ------------------------------------------------------------ | ---------------------------------- | -------- |
| `name`                | `String`           | The name of the Tuist command                                | `cache`                            | true     |
| `subcommand`          | `String`           | The name of the Tuist sub-command                            | `warm`                             | false    |
| `parameters`          | `[String: String]` | A dictionary containing the parameters of the command        | `["verbose" : "true"]`             | false    |
| `durationInMs`        | `Int`              | The duration of the command, in milliseconds                 | `1200`                             | true     |
| `clientId`            | `String`           | An anonymous identifier for the client executing the command | `202cb962ac59075b964b07152d234b70` | true     |
| `tuistVersion`        | `String`           | The version of Tuist when the command run                    | `1.27.0`                           | true     |
| `swiftVersion`        | `String`           | The version of Swift when the command run                    | `5.0`                              | true     |
| `macOSVersion`        | `String`           | The version of macOS when the command run                    | `10.15.7`                          | true     |
| `machineHardwareName` | `String`           | A string identifying the architecture of the operating system | `arm64`                            | true     |
| `isCI` | `Bool`           | Indicates whether Tuist is running in Continuous Integration (CI) environment | true                            | true     |
