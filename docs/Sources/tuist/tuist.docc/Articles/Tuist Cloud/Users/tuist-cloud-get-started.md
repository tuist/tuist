# Get started

Learn how to get started with Tuist Cloud.

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
After the trial period, you'll have to contact [sales@tuist.io](mailto:sales@tuist.io) to get a quote.

## Sign up

Tuist Cloud is CLI-first, meaning that the actions you'd traditionally do on the web, you can do them from the command line.
The first to start using Tuist Cloud is to sign up.
For that, you can run the following command:

```bash
tuist cloud auth
```

## Create an organization

If you are part of an organization to which you want to invite other members, you can create an organization.
Note that this is not necessary if you are working by yourself because you can create projects under your personal account.

```bash
tuist cloud organization create my-organization # Create organization
```

## Create a project

The next step is to create a project. You can easily do that with the following command:

```bash
tuist cloud project create my-project -o my-organization # Create a project
```

After creating the project, modify your `Tuist/Config.swift` file to reference the new project:

```swift
import ProjectDescription

let config = Config(cloud: .cloud(projectId: "my-organization/my-project"))
```

Developers on your team can access the cache if they are authenticated and added as members of the organization, which you can do using the `tuist cloud organization invite` command. For CI environments, authentication is managed differently; it's done using **project-scoped tokens**. These tokens possess restricted permissions compared to those of the organization, including the ability to warm the cache with binaries. To obtain this token, you can execute the following command:


```swift
tuist cloud project token my-project -o my-organization
```

You will then need to set the token as an environment variable named `TUIST_CONFIG_CLOUD_TOKEN` to make it accessible.


> Note: Tuist Cloud relies on Xcode projects being **explicitly defined.** Although we encourage that through the Tuist DSL, implicitness is still possible. If you notice that's causing issues, for example caching not working reliably, send us an email at [help@tuist.io](mailto:help@tuist.io) and we'll help you out.

