# Sessions and Persistence

Every running agent owns a `Condukt.Session`: the `GenServer` that holds
conversation history, tool configuration, and runtime options. By default
sessions live only for the lifetime of the process. A session store lets you
snapshot and restore them.

## Built-in stores

* `Condukt.SessionStore.Memory` keeps snapshots in ETS. Useful for restoring
  state within a running BEAM (for example after a `GenServer` crash).
* `Condukt.SessionStore.Disk` writes snapshots to disk. Useful for crashing
  recovery, deployments, and CLIs.

```elixir
# Restore within the current VM
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: Condukt.SessionStore.Memory,
    session_store_key: {:coding_agent, "/tmp/project"}
  )

# Persist to disk across restarts
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/tmp/project",
    session_store: Condukt.SessionStore.Disk
  )

# Custom path
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Condukt.SessionStore.Disk, path: "/tmp/condukt.session"}
  )
```

When a store is configured, Condukt loads the snapshot at `start_link/1` and
saves a fresh snapshot after every completed turn.

## Store keys and options

Condukt passes `:agent_module`, `:cwd`, an optional `:id`, an optional `:key`,
and any `:session_store_opts` to every store callback. Use
`:session_store_key` when persistence should follow an application domain key
instead of the generated session identifier:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: MyApp.RedisStore,
    session_store_key: "telegram-chat:123",
    session_store_opts: [redix: MyApp.Redix]
  )
```

Stores receive that key as `opts[:key]`. If `:session_store` is passed as a
`{module, opts}` tuple, those tuple options are merged last and can override
the defaults for that store.

## What a snapshot contains

`Condukt.SessionStore.Snapshot` captures the parts of the session that need
to survive a restart: the message history and the configurable options (such
as model, system prompt, and `cwd`). It does not capture transient state
like in flight tool calls.

Assistant history retains opaque provider reasoning details separately from visible
text and thinking summaries. They round-trip through ReqLLM and version-3 snapshots,
including across tool calls. Protect stored snapshots as sensitive conversation data;
provider encryption is not a replacement for the store's access controls. Version-1
and version-2 snapshots still load without inventing missing reasoning state.

## Implementing a store

Implement the `Condukt.SessionStore` behaviour:

```elixir
defmodule MyApp.RedisStore do
  @behaviour Condukt.SessionStore

  @impl true
  def load(opts) do
    redix = Keyword.fetch!(opts, :redix)

    case Redix.command(redix, ["GET", key(opts)]) do
      {:ok, nil} -> :not_found
      {:ok, blob} -> {:ok, :erlang.binary_to_term(blob)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def save(snapshot, opts) do
    redix = Keyword.fetch!(opts, :redix)
    Redix.command(redix, ["SET", key(opts), :erlang.term_to_binary(snapshot)])
    :ok
  end

  @impl true
  def clear(opts) do
    redix = Keyword.fetch!(opts, :redix)
    Redix.command(redix, ["DEL", key(opts)])
    :ok
  end

  defp key(opts), do: "condukt:" <> Keyword.fetch!(opts, :key)
end
```

Then plug it into the agent:

```elixir
MyApp.CodingAgent.start_link(
  session_store: MyApp.RedisStore,
  session_store_key: "user:42",
  session_store_opts: [redix: MyApp.Redix]
)
```

## Clearing history

`Condukt.clear/1` resets the conversation. If a session store is configured,
Condukt also calls the store's `clear/1` callback so persisted state is
removed.
