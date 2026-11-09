---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Run your Amp workspace's orbs on Tuist Sandboxes, on Linux or macOS."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Sandboxes, both Linux and macOS, are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

[Amp](https://ampcode.com) runs each thread's tools in an [orb](https://ampcode.com/docs/orbs), a machine with the thread's repository checked out. Tuist can be your Amp workspace's [self-hosted orb provider](https://ampcode.com/docs/orbs/self-hosted): every thread that picks it runs in its own Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>, on Linux or macOS. You don't run or host anything yourself.

## Connect Amp {#connect}

You need to be an administrator of both the Amp workspace and the Tuist account.

1. In Amp, open your workspace's **Settings → Orbs**, click **Add Orb Provider**, and name it, for example `tuist`. Members pick the provider by this name. Copy the `aop_live_…` token; Amp shows it only once.
2. In the provider's **Edit** dialog in Amp, add these **Orb types** and pick the default:

   | Type | Platform | Shape |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB RAM, 10 GB workspace |
   | `linux-small` | Linux | 2 vCPU, 4 GiB RAM, 10 GB workspace |
   | `macos` | macOS with Xcode | 8 vCPU, 8 GiB RAM, 10 GB workspace |

3. In Tuist, open **Sandboxes** in your account's dashboard, click **Connect** on the Amp card, and paste the token.

The card shows **Connected** once Tuist is serving the provider. One Tuist account serves one provider. Anyone who can use the provider in Amp runs orbs on, and charged to, the connected Tuist account. To stop, click **Disconnect** on the card, or turn the provider off in Amp.

## Start a thread {#start-a-thread}

In Amp's new-thread composer, click **Orb**, choose the Tuist provider under **Self-Hosted**, and pick a type, such as `linux-small` for a repository that needs less than `linux`. From the Amp CLI:

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
