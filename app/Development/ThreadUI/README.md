# Native thread cards (development preview)

NSH 0.3.0 optionally renders structured assistant and tool responses in iOS
Threads. The conversation, glass controls, suggestions, and Markdown fallback
remain SwiftUI. NSH is not enabled in normal project generation; Threads itself
does not require NSH.

From the repository root on an Apple Silicon Mac:

```sh
bash app/Development/prepare_thread_ui.sh
TUIST_THREAD_RICH_UI=true tuist generate --path app --no-open --no-binary-cache
```

Build the TuistApp scheme for an iPhone Simulator and launch with
`--layout-preview`. Open **Improve cache diagnostics** for the change-summary
card. Expand **3 tool actions → Run focused tests** for the test-results card.
Both use sample data; no coding work or pull-request creation runs.

On normal launch, sign in to Tuist. The app loads the signed-in user's feature
flags from the selected server. Users whose flags include `ai` can see Threads
and **Profile → AI subscriptions**, including outside DEBUG builds. Threads uses
account-scoped HTTP APIs and Phoenix revision notifications on that server;
server access additionally requires account administration and private-thread
ownership. New threads require a model selected from the owner's freshly
discovered ChatGPT subscription catalog. The provider/model binding cannot
change after creation; inference refreshes profile credentials on every turn
without falling back to another provider. Claude subscription inference is not
supported by this third-party adapter and is reported as unavailable.
Repository tools run on Tuist sandboxes, not on the phone. Ship requires explicit
approval of a server preview and publishes as the GitHub App without requiring a PR.

Connected profile MCP servers supply namespaced tools, including for threads
without a repository. The server refreshes credentials and checks run ownership
before remote requests. Only Streamable HTTP is supported; discovery errors are
visible, and ambiguous external tool effects block further work rather than
automatically retrying. MCP configuration does not approve Ship or other
unrequested external writes.

Flags refresh on sign-in and foregrounding and clear on sign-out or account
change. In DEBUG builds, `--layout-preview` explicitly enables fixture flags and
sample data; add `--without-ai` to inspect the disabled state. Fixtures cannot
publish changes. These overrides never apply to normal authenticated launches.
Fixture UI checks do not establish live provider, sandbox or GitHub behavior.

The preparation script verifies the pinned release archive and extracts the CLI
and production static XCFramework into `.build/nsh-threads`, then compiles this
bundled renderer. It does not install tools globally or commit binary artifacts.

```sh
.build/nsh-threads/nsh/bin/nsh check app/Development/ThreadUI/App.tsx
.build/nsh-threads/nsh/bin/nsh test app/Development/ThreadUI
```

The earlier standalone Python repository pilot remains available for development
of that harness, but the native app no longer connects to it. Its HTTP contract
is not the authenticated server API:

```sh
/usr/bin/python3 -B app/Development/thread_demo.py --data-dir "$HOME/Library/Application Support/Tuist/thread-demo"
```

The loopback API uses `GET/POST /threads`, `GET /threads/{id}`, and
`POST /threads/{id}/messages`. Lists return `{"threads": [...]}`. The model can
rename a thread with `set_thread_name`. The persisted SQLite names and existing
worktree identities remain unchanged so existing pilot histories still open.

Messages may carry `richContent` with `kind` (`test_results` or `change_summary`),
`title`, `summary`, `facts` (label/value pairs), and `details` (strings), alongside
the mandatory original `content`. No executable code or resource URL is accepted
from a message. Unsupported, oversized, or malformed rich content falls back to
the original Markdown. Missing bundles do the same. A card that does not report
its first layout within five seconds is replaced by Markdown, including when its
bundle fails during startup. Each card also exposes **Original response**.

The pinned NSH 0.3.0 SDK crashes in its native error callback during an injected
JavaScript failure. The host intentionally does not register that callback and
uses the initial-layout deadline instead. Errors after a card has rendered are
not automatically detected; **Original response** remains available. This is a
development preview, not a general-purpose untrusted UI runtime.

Each NSH view owns its runtime. The host and bundle grant only `layout.height`,
a bounded layout notification. There are no network, file, clipboard, URL-opening,
or execution grants and no coding-action handlers. NSH's built-in local Storage
API is not capability-gated; this bundled renderer does not use it. Runtime memory,
node count, and execution time are limited. This initial integration does not load
model-generated code or downloaded signed packages.
