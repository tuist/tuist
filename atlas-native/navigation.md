# Native object navigation

## Decision

Use a **typed destination** (stable native screen key, optional record UUID, HTTPS
server origin), not a global coordinator for feature state and not an arbitrary
web URL. The shell selects the tab and installs a native back stack; the feature
loads its own record through the existing authenticated, fixed-route API.

A UUID alone cannot tell a client its object type or which self-hosted Atlas
instance owns it. Producers must carry that context. There is no global object
lookup request, list scanning, permission bypass, or new navigation dependency.

`core/src/destinations.rs` is the shared capability allowlist. Its immutable C
and primitive-only JNI descriptors tell both clients which screen keys exist
and which accept records. Native adapters use Foundation/Android URL parsing.
Keeping a small adapter on each platform preserves the dependency-free Rust
catalog instead of introducing JNI string ownership or a navigation framework.
The URL parser/coordinator tests pin the security-sensitive grammar.

## Contract

```text
dev.tuist.atlas://navigate/<screen>[/<lowercase-uuid>]?server=<encoded-https-origin>
```

| Screen key | Page | Record |
| --- | --- | --- |
| `tasks` | Tasks | Task detail |
| `accounts` | Accounts | Sales account detail |
| `invoices` | Finance | Invoice detail |
| `time-off` | Employee time off | Not supported |
| `people` | People/presence | Not supported |
| `profile` | Profile | Not supported |

Screen keys are public identifiers once shipped. Changing a title or hierarchy
must not change them. Browser-only catalog entries and AI setup/mutation actions
are deliberately not addressable. Adding another record type requires an
implemented native detail, an authorized server read contract, a core capability,
and adapters/tests on both platforms. Unknown or newer destinations fail closed
with an explanation, never an automatic browser redirect.

Examples:

```text
dev.tuist.atlas://navigate/tasks/123e4567-e89b-12d3-a456-426614174000?server=https%3A%2F%2Fatlas.tuist.dev%2F
dev.tuist.atlas://navigate/time-off?server=https%3A%2F%2Fatlas.example.org%2F
```

There must be exactly one query parameter, `server`. Reject extra path segments,
trailing slashes, encoded path segments, fragments, credentials and ports on the
outer URI, unsupported screens, and malformed/noncanonical UUIDs. Scheme/host
are case-insensitive; screen keys and UUIDs are canonical lowercase. Server
origins must be HTTPS with an ASCII (punycode for international names) host, no
credentials/query/fragment and only an empty or root path. Host case, an optional
root slash, and absent/default 443 are equivalent; nondefault ports must match.
ASCII underscore hosts accepted by the Rust authentication contract are preserved;
raw Unicode host values must instead use punycode. The link never changes the selected server, initiates login, or fills a server
prompt. A mismatched link is dropped with a plain-text explanation.

## Producers and lifecycle

Notifications and other systems should carry a `destination_url` containing the
canonical URI above, not credentials, a record title or an API path. On a user tap,
feed it into the same native ingress used by OS links (`AtlasNavigation.receive`
on iOS and the activity's navigation intent handling on Android). In-process
callers can construct an `AtlasDestination` without building a URL by hand. This
change provides routing, not push registration, delivery or background actions.

- Cold start restores authentication normally. A signed-out link waits for the
  user's normal sign-in, then resolves against the selected server.
- Pending links are latest-wins and memory-only (retained across Android
  configuration changes). They are intentionally lost on process death, never
  persisted as an action to replay in a later user's session.
- Applying, rejecting for server mismatch/draft protection, or signing out clears
  the pending link. Cancelling sign-in does not silently navigate elsewhere.
- OAuth callbacks have their own `oauth-callback` host and never enter workspace
  routing. Android consumes intent data and ignores Recents history replays.
- Links open read-only destinations. Existing API authorization still decides
  whether the record exists and is readable/editable. UUIDs can appear in OS
  history, so URLs must contain no secrets.
- A link cannot interrupt a business/time-off draft, save, or AI setup flow.
  The client explains that the user must finish/discard and reopen the link;
  it does not silently queue a surprise navigation after a save. iOS protection
  retains the owning tab even when hidden (including iPad sidebar switching),
  and AI setup/mutation screens also hide the compact tab bar. Protected views
  dismissed while their tab is hidden must clear their active protection first.
- Records load by ID even when absent from loaded/filtered/paginated lists. Until
  loading succeeds there are no mutation controls or fabricated editable records.
  Failures remain navigable with Back and Retry. Stale/cancelled/session-replaced
  responses cannot resurrect an earlier destination.
- Back from a linked business record returns to its list. Back from People or
  Time off returns to Browse. Business tab models remain stable across links;
  only the addressed native path changes, preserving lists, searches and filters.
  Feature models still own drafts and networking.

## Agent-driven UI automation

Use the normal OS entry point on an already authenticated simulator/emulator:

```sh
xcrun simctl openurl booted \
  'dev.tuist.atlas://navigate/tasks/123e4567-e89b-12d3-a456-426614174000?server=https%3A%2F%2Fatlas.tuist.dev%2F'

adb shell am start -W -a android.intent.action.VIEW \
  -d 'dev.tuist.atlas://navigate/accounts?server=https%3A%2F%2Fatlas.tuist.dev%2F' \
  dev.tuist.atlas
```

Agents then interact with the real native UI and normal authentication. Never
add production fixture arguments, arbitrary API commands, or token injection to
make automation easier. `AtlasNavigationTests`, Rust capability/bridge tests and
Android preview startup checks exercise parsing, lifecycle and direct lookup.
`AtlasNavigationUITests` uses isolated fixture-backed iOS previews, including a
UUID beyond page one, errors, server mismatch, native Back and a warm-link
rejection that preserves a typed AI setup draft. Preview arguments
and fixture authentication remain outside production source globs.

## Research and alternatives

The design was iterated with Claude against the actual catalog, OAuth lifecycle,
business detail APIs, draft ownership and Android recreation paths.

- Apple's [`onOpenURL`](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))
  is the SwiftUI ingress. [`NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack)
  supports data-driven destinations without replacing native UI or feature state.
- Android's [deep-link guidance](https://developer.android.com/training/app-links/deep-linking)
  covers browsable VIEW intent filters and testing with `adb`. Its
  [navigation guidance](https://developer.android.com/guide/navigation/design/deep-link)
  motivates building the expected parent stack, not merely displaying an isolated
  detail. This app uses platform widgets, so it does not need Jetpack Navigation
  solely to handle a small typed route contract.
- Verified HTTPS Universal/App Links are preferable for public shareable links
  when a domain association and web fallback exist. Atlas has arbitrary
  self-hosted origins, and Tasks/Invoices have no equivalent web detail route.
  A custom scheme is the smallest useful transport now. It is **not verified**:
  another app can register it. The payload is therefore untrusted, origin-bound,
  credential-free, read-only, and reauthorized by the server. Verified HTTPS can
  later be another adapter into the same destination type.
- A global UUID resolver would add a server lookup/authorization surface, latency
  and ambiguity across deployments. Typed references avoid all three.
- A universal navigation/state framework or serialized feature models would
  couple unrelated features and make draft/auth lifetimes harder to reason about.
  Only the destination intent belongs to the shell.
