---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# Profiles {#profiles}

A **profile** is an account-scoped, named machine shape. You reference it from a workflow's `runs-on`, and Tuist routes the job to a runner that matches. Profiles keep infrastructure choices (platform, size, Xcode version) in one place instead of scattered across every workflow file, and give you a stable label to point CI at.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

The label is the profile's name with the `tuist-` prefix. A profile named `macos` is `runs-on: tuist-macos`; a profile named `linux-large` is `runs-on: tuist-linux-large`. Matching is case-insensitive.

## Default profiles {#default-profiles}

Every account enabled for Runners starts with two profiles so you can use the fleet without configuring anything:

| Profile | Label           | Default shape                 |
| ------- | --------------- | ----------------------------- |
| `linux` | `tuist-linux`   | 2 vCPU / 8 GB                 |
| `macos` | `tuist-macos`   | 6 vCPU / 14 GB, Xcode 26.5    |

Both point at the default <.localized_link href="/guides/features/runners/profiles#machine-shapes">shape</.localized_link> for their platform. They're **protected**, so they can't be deleted and the `tuist-linux` and `tuist-macos` labels your workflows depend on always resolve. You can still change their shape or Xcode version, and you can create additional profiles for other sizes or Xcode versions.

## Machine shapes {#machine-shapes}

Runners are available on macOS (Apple silicon, virtualized on the Mac fleet) and Linux. Each profile pins one machine shape, a `(vCPUs, memory)` pair, from the catalog below.

### Linux {#linux}

| vCPUs | Memory |
| ----- | ------ |
| 1     | 2 GB   |
| 2     | 4 GB   |
| 2     | 8 GB (default) |
| 4     | 8 GB   |
| 4     | 16 GB  |
| 8     | 16 GB  |
| 8     | 32 GB  |
| 16    | 32 GB  |

### macOS {#macos}

| vCPUs | Memory |
| ----- | ------ |
| 6     | 14 GB (default) |

macOS profiles also pin an **Xcode version**. The version selects a runner image with that Xcode preinstalled, so jobs start with the toolchain already in place. Supported versions today:

- `26.5` (default)
- `26.4.1`
- `26.3`
- `26.0.1`

> [!NOTE]
> The catalog evolves as we add hardware and Xcode releases. The **New profile** form in the dashboard always shows the shapes and Xcode versions currently available to your account, so treat it as the source of truth.

## Creating a profile {#creating-a-profile}

1. Open the **Runners → Profiles** section of your account dashboard.
2. Choose **New profile**.
3. Give it a name, pick a platform, and select a shape. For macOS, also choose an Xcode version.
4. Save, then reference it from a workflow with `runs-on: tuist-<name>`.

For example, a profile named `linux-large` on the 8 vCPU / 32 GB shape:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

Or a macOS profile named `xcode-26-4` pinned to Xcode `26.4.1`, so a job can run on an older toolchain while your default `macos` profile tracks the latest:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
