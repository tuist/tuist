---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "The Tuist CLI, its commands, and how to configure it for your workflow."
}
---
# CLI {#cli}

The Tuist CLI is one of the interfaces for interacting with Tuist, and the most common one if you are using <LocalizedLink href="/guides/features/projects">generated projects</LocalizedLink>. It provides commands for generating projects, caching binaries, running tests, sharing previews, and more.

## Getting started {#getting-started}

If you haven't installed Tuist yet, follow the <LocalizedLink href="/guides/install-tuist">installation guide</LocalizedLink> to get started.

Once installed, you can run `tuist` in your terminal to see a list of available commands:

```bash
tuist --help
```

## Configuration {#configuration}

The CLI behavior can be configured through a `tuist.toml` file. See the <LocalizedLink href="/references/tuist-toml">tuist.toml reference</LocalizedLink> for all available options.

## Troubleshooting {#troubleshooting}

If you run into issues, check the <LocalizedLink href="/cli/debugging">debugging guide</LocalizedLink> for tools to diagnose problems, including session logs and network recordings.
