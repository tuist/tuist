---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Docs {#docs}

Source:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## What it is for {#what-it-is-for}

The docs site hosts Tuist’s product and contributor documentation. It is built
with VitePress.

## How to contribute {#how-to-contribute}

### Set up locally {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Optional generated data {#optional-generated-data}

We embed some generated data in the docs:

- CLI reference data: `mise run generate-cli-docs`
- Project manifest reference data: `mise run generate-manifests-docs`

These are optional. The docs render without them, so only run them when you need
to refresh the generated content.
