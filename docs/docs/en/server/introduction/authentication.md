---
title: Authentication
titleTemplate: :title | Introduction | Server | Tuist
description: Learn how to authenticate with the Tuist server from the CLI.
---

# Authentication

To interact with the server, the CLI needs to authenticate the requests using [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/). The CLI supports authenticating as a user or as a project.

## As a user

When using the CLI locally on your machine, we recommend authenticating as a user. To authenticate as a user, you need to run the following command:

```bash
tuist auth
```

The command will take you through a web-based authentication flow. Once you authenticate, the CLI will store a long-lived refresh token and a short-lived access token under `~/.config/tuist/credentials`. Each file in the directory represents the domain you authenticated against, which by default should be `cloud.tuist.io.json`. The information stored in that directory is sensitive, so **make sure to keep it safe**.

The CLI will automatically look up the credentials when making requests to the server. If the access token is expired, the CLI will use the refresh token to get a new access token.

## As a project

In non-interactive environments like continuous integrations', you can't authenticate through an interactive flow. For those environments, we recommend authenticating as a project by using a project-scoped token:

```bash
tuist project tokens create
```

The CLI expects the token to be defined as the environment variable `TUIST_CONFIG_TOKEN`, and the `CI=1` environment variable to be set. The CLI will use the token to authenticate the requests.

> [!IMPORTANT] LIMITED SCOPE
> The permissions of the project-scoped token are limited to the actions that we consider safe for projects to perform from a CI environment. We plan to document the permissions that the token has in the future.
