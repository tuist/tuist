# Tools

Tools are the things an agent can do beyond generating text. Condukt ships
with a small set of file and shell tools, plus a behaviour for adding your
own.

## Built-in tool sets

```elixir
def tools, do: Condukt.Tools.coding_tools()    # Read, Bash, Edit, Write, Glob, Grep
def tools, do: Condukt.Tools.read_only_tools() # Read, Bash, Glob, Grep
```

You can mix the helpers with extras:

```elixir
def tools do
  Condukt.Tools.read_only_tools() ++ [MyApp.Tools.Weather]
end
```

## Built-in tools

| Tool | Description |
| ---- | ----------- |
| `Condukt.Tools.Read` | Read file contents. Supports images. |
| `Condukt.Tools.Bash` | Run a shell command via `bash -c`. |
| `Condukt.Tools.Command` | Run one trusted executable without shell parsing. |
| `Condukt.Tools.Edit` | Surgical file edits using find and replace. |
| `Condukt.Tools.Write` | Create or overwrite files. |
| `Condukt.Tools.Glob` | Find files by glob pattern. |
| `Condukt.Tools.Grep` | Search file contents by regex. |

## Sandboxes

Built-in tools that touch the filesystem or spawn processes route every call
through the active `Condukt.Sandbox`. The default sandbox,
`Condukt.Sandbox.Local`, talks to the host filesystem. The
`Condukt.Sandbox.Virtual` sandbox runs against an in-memory virtual
filesystem and a Rust-implemented bash interpreter, with no host process
spawning by default. `Condukt.Sandbox.Microsandbox` runs the same tool calls
inside a `microsandbox` microVM while bind-mounted workspace paths still map
back to the host project. The same agent definition works with any of them.

See the [Sandbox guide](sandbox.md) for details, including how to pick a
sandbox at `start_link/1` time and how custom sandboxes plug in.

## Scoped command grants

`Condukt.Tools.Command` is a safer alternative to `Bash` when you want to
expose a single executable without giving the model a full shell. It also
lets you attach trusted environment variables that the model never sees.
Session secrets configured with `:secrets` are merged into that environment.

`Command` does not currently route through the sandbox: it runs the
configured executable directly on the host with the trusted env you provide.
That is intentional. The point of `Command` is the explicit allowlist on the
host side, and it is meant for cases where the host operator wants to grant a
specific tool independently of the agent's general filesystem isolation.

```elixir
defmodule MyApp.ReviewAgent do
  use Condukt

  @impl true
  def tools do
    [
      Condukt.Tools.Read,
      {Condukt.Tools.Command, command: "git"},
      {Condukt.Tools.Command,
       command: "gh",
       env: [GH_TOKEN: System.fetch_env!("GH_TOKEN")]}
    ]
  end
end
```

You can also resolve the token through a secret provider and keep the tool
definition free of plaintext values:

```elixir
MyApp.ReviewAgent.start_link(
  secrets: [
    GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
  ]
)
```

See the [Secrets guide](secrets.md) for provider-backed configuration and
redaction behavior.

Each scoped command tool accepts:

* `args` is an array of strings passed directly to the executable
* `cwd` overrides the agent's working directory for this call
* `timeout` caps execution time in seconds

## Defining a custom tool

Implement `Condukt.Tool`:

```elixir
defmodule MyApp.Tools.Weather do
  use Condukt.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Gets the current weather for a location"

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City name"}
      },
      required: ["location"]
    }
  end

  @impl true
  def call(%{"location" => location}, _context) do
    case WeatherAPI.get(location) do
      {:ok, data} -> {:ok, "Temperature: #{data.temp}F"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

The second argument to `call/2` is a context map that includes:

* `:agent` is the agent PID
* `:agent_module` is the agent module for the session
* `:sandbox` is the active `Condukt.Sandbox` struct
* `:cwd` is the project working directory (use `:sandbox` for any file or
  command work; `:cwd` is for resolving project-relative paths that aren't
  themselves I/O operations)
* `:secrets` contains resolved session secrets for trusted tools
* `:opts` is the keyword list from `{Module, opts}`
* `:assigns` is a map of session-scoped values populated by previous tool
  calls. See [Sharing state across tool calls](#sharing-state-across-tool-calls).

## Sandbox-aware tools

If your tool reads or writes files, or runs subprocesses, route through the
`Condukt.Sandbox.*` facade rather than calling `File.*`, `System.cmd/3`, or
`MuonTrap.cmd/3` directly. Direct calls bypass the sandbox and break the
ability to swap one in.

```elixir
defmodule MyApp.Tools.LineCount do
  use Condukt.Tool

  alias Condukt.Sandbox

  @impl true
  def name, do: "line_count"

  @impl true
  def description, do: "Counts lines in a file"

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{path: %{type: "string"}},
      required: ["path"]
    }
  end

  @impl true
  def call(%{"path" => path}, %{sandbox: sandbox}) do
    case Sandbox.read(sandbox, path) do
      {:ok, content} -> {:ok, content |> String.split("\n") |> length()}
      {:error, reason} -> {:error, "cannot read #{path}: #{inspect(reason)}"}
    end
  end
end
```

Tools that touch unrelated systems (HTTP APIs, databases, in-process state)
have nothing to sandbox and can do their I/O directly.

## Inline tools

Use `Condukt.tool/1` for one-off runs where defining a module would add
more ceremony than value. Inline tools work anywhere a module tool works,
including an agent's `tools/0` callback and anonymous `Condukt.run/2` calls.

```elixir
weather =
  Condukt.tool(
    name: "weather",
    description: "Returns the weather for a city",
    parameters: %{
      type: "object",
      properties: %{city: %{type: "string"}},
      required: ["city"]
    },
    call: fn %{"city" => city}, _context ->
      {:ok, "72F in #{city}"}
    end
  )

{:ok, response} =
  Condukt.run("What is the weather in Berlin?",
    tools: [weather]
  )
```

The callback receives the same context map as module tools. If it touches the
filesystem or runs commands, use `context.sandbox` through `Condukt.Sandbox`.

## Parameterized tools

Tools can be added more than once with different options. The `name/1`,
`description/1`, and `parameters/1` callbacks receive those options:

```elixir
defmodule MyApp.Tools.Database do
  use Condukt.Tool

  @impl true
  def name(opts), do: "query_#{opts[:table]}"

  @impl true
  def description(opts), do: "Query the #{opts[:table]} table"

  @impl true
  def parameters(_opts) do
    %{type: "object", properties: %{q: %{type: "string"}}, required: ["q"]}
  end

  @impl true
  def call(args, context) do
    table = context.opts[:table]
    {:ok, MyApp.Repo.query!(table, args["q"])}
  end
end

# In the agent:
def tools do
  [
    {MyApp.Tools.Database, table: "users"},
    {MyApp.Tools.Database, table: "orders"}
  ]
end
```

## Returning results

`call/2` should return:

* `{:ok, value}` for success. Strings, maps, and lists are all fine. Non
  binary values are JSON encoded before being sent to the LLM.
* `{:ok, value, assigns}` for success with state. The `assigns` map is
  merged into the session's `:assigns` so later tools can read it. See
  the next section.
* `{:error, reason}` for failures. The error is reported back to the model
  so it can recover.

## Sharing state across tool calls

Tools in a single agent run often need to refer to facts established by
earlier tools: an account id from a lookup, a parsed config, a session
token. Returning a third element from the success tuple, ExUnit-style,
merges values into the session's `assigns` map. Subsequent tool calls
read them as `context.assigns[:key]`:

```elixir
find_account =
  Condukt.tool(
    name: "find_account",
    description: "Looks up an account by email",
    parameters: %{
      type: "object",
      properties: %{email: %{type: "string"}},
      required: ["email"]
    },
    call: fn %{"email" => email}, _ctx ->
      case Accounts.find_by_email(email) do
        {:ok, account} ->
          {:ok, %{found: true, account: account}, %{found_account_id: account.id}}

        :error ->
          {:ok, %{found: false}}
      end
    end
  )

store_event =
  Condukt.tool(
    name: "store_event",
    description: "Stores an event on the matched account",
    parameters: %{
      type: "object",
      properties: %{title: %{type: "string"}},
      required: ["title"]
    },
    call: fn %{"title" => title}, ctx ->
      case ctx.assigns[:found_account_id] do
        nil ->
          {:error, "call find_account first"}

        id ->
          {:ok, Events.create!(account_id: id, title: title)}
      end
    end
  )
```

Returned maps are merged into the session's `:assigns` last-write-wins,
matching `Phoenix.Component.assign/3`. Assigns persist for the lifetime
of the session, so they remain visible across multiple `Condukt.run/2`
calls on the same agent process.

You can also seed assigns when starting a session:

```elixir
{:ok, agent} =
  MyAgent.start_link(assigns: %{tenant_id: "acme"})
```

Within a single batch of tool calls in one assistant message, all tools
see the same start-of-batch snapshot of `:assigns`; their returned maps
are merged after the batch and visible in the next turn. If the LLM
proposes tools A and B together and B needs A's update, prompt the model
to call them in separate turns.
