---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Gather insights {#gather-insights}

Tuist can integrate with a server to extend its capabilities. One of those
capabilities is gathering insights about your project and builds. All you need
is to have an account with a project in the server.

First of all, you'll need to authenticate by running:

```bash
tuist auth login
```

## Create a project {#create-a-project}

You can then create a project by running:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Copy `my-handle/MyApp`, which represents the full handle of the project.

## Connect projects {#connect-projects}

After creating the project on the server, you'll have to connect it to your
local project. Run `tuist edit` and edit the `Tuist.swift` file to include the
full handle of the project:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Voilà! You're now ready to gather insights about your project and builds. Run
`tuist test` to run the tests reporting the results to the server.

::: info
<!-- -->
Tuist enqueues the results locally and tries to send them without blocking the
command. Therefore, they might not be sent immediately after the command
finishes. In CI, the results are sent immediately.
<!-- -->
:::


![An image that shows a list of runs in the
server](/images/guides/quick-start/runs.png)

Having data from your projects and builds is crucial in making informed
decisions. Tuist will continue to extend its capabilities, and you'll benefit
from them without having to change your project configuration. Magic, right? 🪄
