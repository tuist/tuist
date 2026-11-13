# Secrets

Agent sessions often need credentials to do useful work: a GitHub token for
`gh`, an API key for a deploy tool, or a database URL for a local smoke test.
The unsafe version is to paste those values into the prompt or check them into
an `.env` file the agent can read. Condukt's secrets API keeps the declaration
in trusted code and exposes the resolved values only to tool execution
environments.

## How other agents handle this

Most agent runtimes have converged on one of a few patterns:

* CLI agents such as Claude Code and Aider read credentials from environment
  variables, `.env` files, or configuration files.
* Cloud agents such as GitHub Copilot coding agent prepare an ephemeral
  development environment and let users attach GitHub Actions variables or
  secrets to that environment.
* Secret managers such as 1Password avoid plaintext files by resolving secret
  references at runtime. `op run` is the canonical example: it makes secrets
  available as environment variables only for the subprocess it starts.
* MCP authorization is moving toward OAuth-based delegated access for remote
  tools. That is the right shape for tools that represent SaaS APIs, but it
  does not replace local tool credentials like `GH_TOKEN`.

Condukt follows the same separation of concerns: secrets are resolved by
trusted host code, scoped to a session, injected into tool subprocess
environments, and kept out of model context.

## Configuring secrets

Pass `:secrets` at `start_link/1`, return it from an agent module's
`secrets/0` callback, or configure it through `config :condukt, :secrets`.
Keys are the environment variable names exposed to command tools.

```elixir
defmodule MyApp.ReviewAgent do
  use Condukt

  @impl true
  def tools do
    [
      Condukt.Tools.Read,
      {Condukt.Tools.Command, command: "gh"}
    ]
  end

  @impl true
  def secrets do
    [
      GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
    ]
  end
end
```

The same declaration can be provided per session:

```elixir
{:ok, agent} =
  MyApp.ReviewAgent.start_link(
    secrets: [
      GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"},
      DATABASE_URL: {:env, "DATABASE_URL"}
    ]
  )
```

Built-in provider aliases are:

| Alias | Provider | Purpose |
| ----- | -------- | ------- |
| `:one_password` or `:op` | `Condukt.Secrets.Providers.OnePassword` | Resolves a 1Password secret reference with `op read`. |
| `:env` | `Condukt.Secrets.Providers.Env` | Copies a value from the host process environment. |
| `:static` | `Condukt.Secrets.Providers.Static` | Uses a trusted plaintext value. Prefer this for tests. |

Later declarations for the same environment variable replace earlier ones.

## 1Password

The 1Password provider shells out to `op read <ref>` while the session starts.
Authenticate `op` first, or start Condukt with an `OP_SERVICE_ACCOUNT_TOKEN`
that is scoped to the vaults the agent needs.

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    secrets: [
      GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"},
      STRIPE_API_KEY:
        {Condukt.Secrets.Providers.OnePassword,
         ref: "op://Engineering/Stripe/api-key",
         account: "acme"}
    ]
  )
```

Secret references stay in code. The plaintext value is loaded into the BEAM
process at session initialization and then passed to tool subprocesses as an
environment variable.

## Tool execution

`Condukt.Tools.Bash` passes session secrets through
`Condukt.Sandbox.exec/3` as environment variables:

```elixir
Condukt.run(agent, "Run the local smoke test that needs DATABASE_URL")
```

`Condukt.Tools.Command` merges session secrets with the trusted `:env` values
configured on the tool. Session secrets win if both define the same variable.

```elixir
def tools do
  [
    {Condukt.Tools.Command, command: "gh", env: [GH_HOST: "github.com"]}
  ]
end
```

The model cannot add or change environment variables through tool arguments.
It can only invoke the tools you configured.

## Auditing access

Condukt emits value-free telemetry for secret resolution and access:

* `[:condukt, :secrets, :resolve]` when a session resolves secrets.
* `[:condukt, :secrets, :access]` when a tool receives resolved secrets.

Both events include `count` as a measurement and `:names` metadata with
environment variable names such as `["GH_TOKEN"]`. Access events also include
`:tool`, and include `:tool_call_id` when the access comes from a concrete
provider-returned tool call. Secret values are never included in measurements
or metadata.

Attach a handler if you want an audit trail:

```elixir
:telemetry.attach(
  "secret-access-audit",
  [:condukt, :secrets, :access],
  fn _event, measurements, metadata, _config ->
    Logger.info("agent secret access",
      count: measurements.count,
      agent: inspect(metadata.agent),
      tool: metadata.tool,
      names: metadata.names
    )
  end,
  nil
)
```

## Custom providers

Implement `Condukt.SecretProvider` when your secrets live somewhere else:

```elixir
defmodule MyApp.Secrets.Vault do
  @behaviour Condukt.SecretProvider

  @impl true
  def load(opts) do
    MyApp.Vault.read(Keyword.fetch!(opts, :path))
  end
end

{:ok, agent} =
  MyApp.Agent.start_link(
    secrets: [
      INTERNAL_TOKEN: {MyApp.Secrets.Vault, path: "agents/internal-token"}
    ]
  )
```

`load/1` returns `{:ok, value}` or `{:error, reason}`. If any secret fails to
load, the session fails to start.

## Redaction and persistence

Resolved secrets are not added to:

* The system prompt
* User messages
* LLM request options
* Session store snapshots

If a tool prints a resolved secret, Condukt exact-match redacts the value from
the tool result before it is stored in history, streamed to subscribers, or
sent back to the model:

```text
[REDACTED:GH_TOKEN]
```

Values shorter than four bytes are not redacted because replacing tiny strings
causes too many false positives.

Under the hood, resolved session secrets become a
`Condukt.Redactors.Secrets` spec and are composed with the session's configured
`:redactor`. Secret redaction runs first so custom redactors cannot transform a
secret before the exact-match replacement has a chance to run.

Redaction is a safety layer, not a permission model. A tool subprocess that
receives `GH_TOKEN` can use it. Scope tokens and 1Password service accounts to
the smallest set of resources that the session needs.
