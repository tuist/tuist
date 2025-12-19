---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Get started {#get-started}

The easiest way to get started with Tuist in any directory or in the directory
of your Xcode project or workspace:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

The command will walk you through the steps to
<LocalizedLink href="/guides/features/projects">create a generated project</LocalizedLink> or integrate an existing Xcode project or workspace. It
helps you connect your setup to the remote server, giving you access to features
like <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">previews</LocalizedLink>, and
the <LocalizedLink href="/guides/features/registry">registry</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
If you want to migrate an existing project to generated projects to improve the
developer experience and take advantage of our
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, check out
our
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">migration guide</LocalizedLink>.
<!-- -->
:::
