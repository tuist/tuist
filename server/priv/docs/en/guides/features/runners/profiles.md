---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# Profiles {#profiles}

> [!IMPORTANT]
> **Invite-only**
>
> Profiles are part of <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, which is currently invite-only. [Reach out](mailto:contact@tuist.dev) to request access.


A **profile** is an account-scoped, named machine shape. You reference it from a workflow's `runs-on`, and Tuist routes the job to a runner that matches. Profiles keep infrastructure choices (platform, size, Xcode version) in one place instead of scattered across every workflow file, and give you a stable label to point CI at.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

The label is the profile's name with the `tuist-` prefix. A profile named `macos` is `runs-on: tuist-macos`; a profile named `linux-large` is `runs-on: tuist-linux-large`. Matching is case-insensitive.

## Default profiles {#default-profiles}

Every account enabled for Runners starts with two profiles so you can use the fleet without configuring anything:

| Profile | Label           | Shape                        |
| ------- | --------------- | ---------------------------- |
| `linux` | `tuist-linux`   | Default Linux shape          |
| `macos` | `tuist-macos`   | Default macOS shape + Xcode  |

These two are **protected**: they can't be deleted, so the labels your workflows depend on stay valid. You can create additional profiles for other sizes or Xcode versions.

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

## Fields {#fields}

| Field           | Applies to     | Notes |
| --------------- | -------------- | ----- |
| **Name**        | all            | Lowercase letters, digits, and hyphens; must start with a letter; up to 32 characters. Unique within your account and **immutable after creation**, so the label your workflows use never changes underneath them. |
| **Platform**    | all            | `linux` or `macos`. |
| **vCPUs / Memory** | all         | A `(vCPUs, memory)` pair from the <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape catalog</.localized_link> for the chosen platform. |
| **Xcode version** | macOS        | The Xcode release preinstalled on the runner image. Required for macOS profiles, ignored for Linux. |

> [!NOTE]
> `runner`, `runners`, and `tuist` are reserved and can't be used as profile names, so labels like `tuist-tuist` never appear.

## Creating a profile {#creating-a-profile}

1. Open the **Runners → Profiles** section of your account dashboard.
2. Choose **New profile**.
3. Give it a name, pick a platform, and select a shape. For macOS, also choose an Xcode version. The form only offers shapes and Xcode versions currently available to your account.
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

## Limits {#limits}

- Up to **10 profiles** per account.
- A profile's **name can't be changed** once created. To "rename", create a new profile and update your workflows to point at it, then delete the old one.
- **Protected** profiles (the default `linux` and `macos`) can't be deleted.
