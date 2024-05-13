---
title: Get started with Tuist Cloud
titleTemplate: ':title - Tuist Cloud'
description: Get started with Tuist Cloud, a Tuist extension that ensures your projects are healthy and productive.
---

# Get started with Tuist Cloud

To start using Tuist Cloud, you need to have a project that you managed through the Tuist. If you don't have one, we recommend starting from the [installation guide](/guide/introduction/installation).

<!-- 
## Pricing

Tuist Cloud is **free within the same environment.**
You don't need to sign up at all for that.
For example, developers can cache their binaries to speed up their clean builds.

**When using it across environments,**
for example to speed up CI builds with artifacts from previous builds,
or local builds with artifacts generated in CI,
that's part of the paid offering.
Tuist Cloud is free during the first 30 days with a limit of 10GB which can be extended by reaching out to us.
This period is meant to allow you to evaluate the service and understand how it fits your needs.
After the trial period, you'll have to contact [sales@tuist.io](mailto:sales@tuist.io) to get a quote. -->

Tuist Cloud is CLI-first, meaning that the actions you'd traditionally do on the web, you can do them from the command line.
The first to start using Tuist Cloud is to **sign up**.
For that, you can run the following command:

```bash
tuist cloud auth
```

> [!TIP] ORGANIZATION AND USERS
> Like [GitHub](https://github.com) you projects (repositories in the context of GitHub) can be part of an organizations or your personal account. Account and organizations have handles, which are unique across the platform. For example, the Tuist organization uses the `tuist` handle.

## Create an organization <Badge type="info">Optional</Badge>

If you are part of an organization to which you want to invite other members, you can create an organization.

> [!NOTE]
> This is not necessary if you are working by yourself because you can create projects under your personal account.

```bash
tuist cloud organization create my-organization # Create organization
```

### Organization SSO

If you have a Google Workspace organization and you want any developer who signs in with the same Google hosted domain to be added to your Tuist organization, you can set it up with:
```bash
tuist cloud organization update sso my-organization --provider google --organization-id my-domain.com
```

## Create a project

The next step is to create a project. You can easily do that with the following command:

::: code-group
```bash [Project under user account]
tuist cloud project create my-project
```
```bash [Project under organization]
tuist cloud project create my-project -o my-organization
```
:::

After creating the project, modify your `Tuist/Config.swift` file to reference the new project:

```swift
import ProjectDescription

let config = Config(cloud: .cloud(projectId: "my-organization/my-project"))
```

> [!TIP] PROJECT IDENTIFIER
> The project identifier is formed by concatenating the organization or user handle and the project handle with a slash. For example, the Tuist organization uses the `tuist` handle, and the project is named `tuist`. The project identifier would be `tuist/tuist`.

## Authentication

### As user

Developers on your team can access Tuist Cloud if they are authenticated and added as members of the organization, which you can do using the `tuist cloud organization invite` command. 

### As project (e.g. for CI)
For CI environments, authentication is managed differently; it's done using **project-scoped tokens**. These tokens possess restricted permissions compared to those of the organization, including the ability to warm the cache with binaries. To obtain this token, you can execute the following command:


```bash
tuist cloud project token my-project -o my-organization
```

You will then need to set the token as an environment variable named `TUIST_CONFIG_CLOUD_TOKEN` to make it accessible.

> [!NOTE] EXPOSING SECRET ENVIRONMENT VARIABLES IN CI ENVIRONMENTS
> How environment secret environment variables are exposed in CI environments varies depending on the CI provider. Ensure you follow the guidelines provided by your CI provider to securely manage these tokens. 

## Tuist and Tuist Cloud integration

When the Tuist Cloud configuration is set up, and there's a valid session, either as a user or project, Tuist Cloud features will be available automatically without any additional configuration or actions. This is the beauty of Tuist Cloud's setup–it doesn't require the installation of additional tools, plumbing, or configuration. It just works™.