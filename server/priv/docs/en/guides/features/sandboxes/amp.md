---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Run your Amp workspace's orbs on Tuist Sandboxes, on Linux or macOS, or give any Amp thread a Mac for Xcode builds with the Tuist Mac plugin."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Sandboxes, both Linux and macOS, are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

[Amp](https://ampcode.com) runs each thread's tools in an [orb](https://ampcode.com/docs/orbs), a machine with the thread's repository checked out. Tuist can be your Amp workspace's [self-hosted orb provider](https://ampcode.com/docs/orbs/self-hosted): every thread that picks it runs in its own Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>, on Linux or macOS. You don't run or host anything yourself.

To keep your threads on their current orbs and only build, test and run Apple-platform code on a Mac, use the [Tuist Mac plugin](#remote-mac) instead.

## Connect Amp {#connect}

You need to be an administrator of both the Amp workspace and the Tuist account.

1. In Amp, open your workspace's **Settings → Orbs**, click **Add Orb Provider**, and name it, for example `tuist`. Members pick the provider by this name. Copy the `aop_live_…` token; Amp shows it only once.
2. In the provider's **Edit** dialog in Amp, add the **Orb types** you want to offer and pick the default. The Linux types match the sizes of [Amp's own orbs](https://ampcode.com/docs/orbs/sizes-and-costs):

   | Type | Platform | Shape |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB RAM, 10 GB workspace |
   | `linux-tiny` | Linux | 1 vCPU, 2 GiB RAM, 10 GB workspace |
   | `linux-small` | Linux | 2 vCPU, 4 GiB RAM, 10 GB workspace |
   | `linux-medium` | Linux | 4 vCPU, 8 GiB RAM, 10 GB workspace (same as `linux`) |
   | `linux-large` | Linux | 8 vCPU, 16 GiB RAM, 10 GB workspace |
   | `linux-xxlarge` | Linux | 16 vCPU, 32 GiB RAM, 10 GB workspace |
   | `linux-3xlarge` | Linux | 16 vCPU, 44 GiB RAM, 10 GB workspace |
   | `macos` | macOS with Xcode | 8 vCPU, 8 GiB RAM, 10 GB workspace |

3. In Tuist, open **Sandboxes** in your account's dashboard, click **Connect** on the Amp card, and paste the token.

The card shows **Connected** once Tuist is serving the provider. One Tuist account serves one provider. Anyone who can use the provider in Amp runs orbs on, and charged to, the connected Tuist account. To stop, click **Disconnect** on the card, or turn the provider off in Amp.

## Start a thread {#start-a-thread}

In Amp's new-thread composer, click **Orb**, choose the Tuist provider under **Self-Hosted**, and pick a type, such as `linux-small` for a repository that needs less than `linux`, or `linux-large` for one that needs more. From the Amp CLI:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

A thread keeps its orb type for life. Without a type, it gets the provider's default. To use one type for every new thread, choose the provider and its type under **Default Orb** in Amp's **Settings → Orbs**.

Amp clones the repository, runs your `.agents/setup` script and sets up Git credentials, as it does for every orb. Each orb can also read your account's Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>.

## Pausing and retention {#retention}

When a thread goes idle, Amp pauses its orb. The next message resumes it with its files intact.

- **Linux:** Running processes survive a pause. An orb that has been paused for a long time moves to archive storage and is restored on the next message, without its processes. Linux orbs keep their files until Amp deletes the thread's orb.
- **macOS:** An orb paused, or in an error state, for 7 days is deleted. The thread's next message starts a fresh orb, and Amp runs `.agents/setup` again. The first macOS orb on a machine installs the Amp CLI, so it can take up to two minutes to start.

An orb that stays idle without Amp pausing it, for example because a pause never arrived, is paused after ten minutes with almost no CPU use.

## Use a Mac from any Amp thread {#remote-mac}

The Tuist Mac plugin gives an Amp thread a macOS sandbox with Xcode, the iOS simulators and Homebrew while the thread keeps running where it is, for example on one of Amp's own Linux orbs. Ask Amp for the work, and it starts a Mac when it needs one:

> Add a dark mode toggle to the settings screen, run the app in the iOS Simulator, and show me a screenshot.

Amp keeps editing code where it runs. Before each command on the Mac, the plugin runs `tuist sandbox sync`, which copies the files Git doesn't ignore, committed or not, and afterwards only the ones that changed. Build products and other ignored files the Mac creates stay there, so builds stay incremental. The plugin adds these tools, and a `remote-mac` skill that tells Amp when and how to use them:

| Tool | What it does |
| --- | --- |
| `tuist_mac_start` | Creates the thread's Mac, or reuses it, and syncs |
| `tuist_mac_shell` | Syncs, then runs a command on the Mac |
| `tuist_mac_screenshot` | Shows the simulator or the screen in the thread |
| `tuist_mac_download` | Copies a file back, such as a built `.app` |
| `tuist_mac_stop` | Deletes the thread's Mac |

A thread uses one Mac. Tuist pauses it when it's idle and the next command resumes it. Amp deletes it when the task is done; a Mac left behind is deleted after 14 days paused. Macs count toward your Tuist account like any other sandbox.

### Set it up {#remote-mac-setup}

1. **Install the plugin.** It's one file, [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). To make it available to everyone in your Amp workspace, a workspace admin asks Amp in a thread:

   > Add https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts to our workspace plugins.

   Amp commits it to the workspace's [plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills) and asks before pushing it. Ask for "my personal plugins" instead to install it only for yourself, or save the file as `.amp/plugins/tuist-mac.ts` in a repository to use it only there. The plugin is a copy: to update it, ask Amp to replace it with the latest version from the same URL.
2. **Install the Tuist CLI** where Amp runs. The plugin needs a version with `tuist sandbox sync`, 4.218.0 or later. On orbs, add it to the repository's [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) script, for example `mise use -g tuist@<version>`, or `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **Let the CLI use your account's sandboxes.** On orbs, connect your Amp workspace to your Tuist account as described in <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>. The orbs then sign in on their own, with access to sandboxes. Elsewhere, such as the Amp CLI on a Linux machine, run `tuist auth login` as an account member, or set `TUIST_MAC_TOKEN` to an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `account:sandboxes:write` scope. The plugin passes `TUIST_MAC_TOKEN` to the CLI in place of `TUIST_TOKEN`, so also set it when your orbs already have a `TUIST_TOKEN` without that scope.
4. **Tell it which account to use**, if the repository has no `tuist.toml` with `project = "<account>/<project>"`. On Linux, the CLI can't read the account from `Tuist.swift`. Set `TUIST_MAC_ACCOUNT` to your account handle in your Amp project's environment variables. Without it, Amp passes the account from `Tuist.swift`'s `fullHandle` to `tuist_mac_start`.

The CLI reaches the Mac only through `tuist.dev`, so an environment that restricts network access needs to allow only that domain. To try another CLI build, such as a canary, set `TUIST_MAC_CLI` to its path.

Agents that don't support Amp plugins, such as Claude Code or Cursor, can do the same through the Tuist MCP server and the CLI, as described in <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>.
