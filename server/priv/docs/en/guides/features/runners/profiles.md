---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, Ubuntu release or Xcode version for Tuist Runners."
}
---
# Profiles {#profiles}

A **profile** is an account-scoped, named machine shape. You reference it from a workflow's `runs-on`, and Tuist routes the job to a runner that matches. Profiles keep infrastructure choices (platform, size, Ubuntu release or Xcode version) in one place instead of scattered across every workflow file, and give you a stable label to point CI at.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

The label is the profile's name with the `tuist-` prefix. A profile named `macos` is `runs-on: tuist-macos`; a profile named `linux-large` is `runs-on: tuist-linux-large`. Matching is case-insensitive.

## Default profiles {#default-profiles}

Every account enabled for Runners starts with two profiles so you can use the fleet without configuring anything:

{{runner_default_profiles_table}}

Both point at the default <.localized_link href="/guides/features/runners/profiles#machine-shapes">shape</.localized_link> for their platform. They're **protected**, so they can't be deleted and the labels your workflows depend on always resolve. You can still change their shape or Xcode version, and you can create additional profiles for other sizes or Xcode versions.

## Machine shapes {#machine-shapes}

Runners are available on macOS (Apple silicon, virtualized on the Mac fleet) and Linux. Each profile pins one machine shape, a `(vCPUs, memory)` pair, from the catalog below.

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux profiles also pick an **Ubuntu release**, the way macOS profiles pick an Xcode version:

- **Ubuntu 24.04** (`ubuntu-24.04`), the default for new profiles.
- **Ubuntu 22.04** (`ubuntu-22.04`), for workflows that still need it. GitHub deprecated its 22.04 hosted image and removes it on April 17, 2027; plan to move off it by then.

A profile stays on the release you chose until you change it, so a newer default never moves your jobs to another OS on its own. Binaries built on 24.04 need its newer glibc (2.39) and may not run on older systems, and its system Python refuses `pip install` outside a virtual environment (PEP 668). The runner sets `ImageOS` (`ubuntu24` or `ubuntu22`) as GitHub-hosted runners do, so setup actions pick builds for the right release.

Every Linux profile supports <.localized_link href="/guides/features/runners#android-emulators">hardware-accelerated Android emulators</.localized_link> through `/dev/kvm`. No separate KVM profile is required.

### macOS {#macos}

{{runner_macos_shapes_table}}

Larger macOS shapes run on fewer machines in the fleet, so a job that asks for one can wait longer to start than the same job on a smaller shape. Reach for a larger shape when a job is limited by CPU, and keep the default shape for everything else. If you are not sure, run the job on both and compare the durations in the dashboard.

macOS profiles also pin an **Xcode version**. The version selects a runner image with that Xcode preinstalled, so jobs start with the toolchain already in place. Supported versions today:

{{runner_macos_xcode_versions}}

> [!NOTE]
> The catalog evolves as we add hardware and Xcode releases. The **New profile** form in the dashboard and `tuist runner profile catalog` always show the shapes, Xcode versions and Ubuntu releases currently available to your account, so treat them as the source of truth.

A macOS runner's name shows the macOS version it runs, the profile's Xcode version, and its shape, for example `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`. The name appears in the job's **Set up job** step on GitHub and in the job's details in the Tuist dashboard.

## Creating a profile {#creating-a-profile}

1. Open the **Runners → Profiles** section of your account dashboard.
2. Choose **New profile**.
3. Give it a name, pick a platform, and select a shape. For Linux, also choose an Ubuntu release; for macOS, an Xcode version.
4. Save, then reference it from a workflow with `runs-on: tuist-<name>`.

You can also manage profiles from the command line. Creating, changing, and deleting profiles requires account administration, as in the dashboard, or an account token with the `account:runners:write` scope:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agents can do the same through the <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>.

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
