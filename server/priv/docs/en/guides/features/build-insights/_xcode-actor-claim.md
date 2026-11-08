## Report actor claim {#report-actor-claim}

Report-creation requests include the optional `x-tuist-actor-id` header only when you explicitly set `TUIST_ACTOR_ID` to an organization-scoped label, for example `TUIST_ACTOR_ID=employee-123 tuist inspect build`. No label is sent by default, and Tuist does not detect operating-system usernames. An empty `TUIST_ACTOR_ID` omits the reported identifier but does not remove credential-based verified identity. Identifiers must be 1–128 bytes of non-space printable ASCII; invalid overrides are omitted without falling back. If a custom proxy rejects unfamiliar headers, opt out with the empty environment override.

Verified individual credentials take precedence; client-reported identifiers are otherwise shown as **Unverified** and never grant permissions or link automatically to users. Identifiers are visible to anyone who can view the project's reports, including public viewers when the project is public, and included in data exports, so do not include secrets. This applies to build, test, and command-event reports. Old servers ignore the optional header, and new servers accept old clients without it. New shared-token reports with no identifier show **Unknown**, rather than the publishing organization; historical reports retain their prior attribution. Build and test listings distinguish verified users from unverified reported identifiers. Authentication remains required unless the self-hosted instance explicitly enables credential-free reporting and the client discovers that policy.

### Scheme post-actions {#actor-claim-post-actions}

Actor claims are disabled by default. To configure one for a scheme post-action, set `TUIST_ACTOR_ID` in that script rather than relying on shell exports. Xcode launched from the Dock does not inherit variables from `~/.zshrc`. To explicitly suppress a configured claim with Homebrew, use:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

With Mise, override the value after Mise loads its environment:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

Use an explicit label instead of the empty value to opt in.
