---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Accounts and projects {#accounts-and-projects}

Some Tuist features require a server which adds persistence of data and can interact with other services. To interact with the server, you need an account and a project that you connect to your local project.

## Accounts {#accounts}

To use the server, you'll need an account. There are two types of accounts:

- **Personal account:** Those accounts are created automaticaly when you sign up and are identified by a handle that's obtained either from the identity provider (e.g. GitHub) or the first part of the email address.
- **Organization account:** Those accounts are manually created and are identified by a handle that's defined by the developer. Organizations allow inviting other members to collaborate on projects.

If you are familiar with [GitHub](https://github.com), the concept is similar to theirs, where you can have personal and organization accounts, and they are identified by a *handle* that's used when constructing URLs.

::: info CLI-FIRST
<!-- -->
Most operations to manage accounts and projects are done through the CLI. We are working on a web interface that will make it easier to manage accounts and projects.
<!-- -->
:::

You can manage the organization through the subcommands under <LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>. To create a new organization account, run:
```bash
tuist organization create {account-handle}
```

## Projects {#projects}

Your projects, either Tuist's or raw Xcode's, need to be integrated with your account through a remote project. Continuing with the comparison with GitHub, it's like having a local and a remote repository where you push your changes. You can use the <LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> to create and manage projects.

Projects are identified by a full handle, which is the result of concatenating the organization handle and the project handle. For example, if you have an organization with the handle `tuist`, and a project with the handle `tuist`, the full handle would be `tuist/tuist`.

The binding between the local and the remote project is done through the configuration file. If you don't have any, create it at `Tuist.swift` and add the following content:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
Note that there are some features like <LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink> that require you having a Tuist project. If you are using raw Xcode projects, you won't be able to use those features.
<!-- -->
:::

Your project's URL is constructed by using the full handle. For example, Tuist's dashboard, which is public, is accessible at [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), where `tuist/tuist` is the project's full handle.
