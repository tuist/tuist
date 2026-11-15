defmodule Condukt.Sessions.Registry do
  @moduledoc """
  Behaviour for where `Condukt.Sessions` registers sessions by id.

  The registry decides which sessions an id reaches. The default,
  `Condukt.Sessions.Registry.Local`, uses Elixir's `Registry` and sees the
  sessions on the local node only. `Condukt.Sessions.Registry.PG` uses `:pg`
  and sees the sessions on every connected node, and
  `Condukt.Sessions.Registry.Horde` does the same on `Horde.Registry`, so
  `Condukt.signal/4`, `run/3`, and the rest of the session API reach a session
  by id from any node.

  Configure one before `:condukt` starts:

      config :condukt, session_registry: Condukt.Sessions.Registry.PG

      # Or with options, passed to every callback
      config :condukt, session_registry: {Condukt.Sessions.Registry.PG, scope: MyApp.Sessions}

  ## Implementing one

  Sessions are named with the `{:via, module, name}` tuple `c:via/2` returns,
  so the adapter plugs into OTP's own name registration. The `module` in that
  tuple implements `register_name/2`, `unregister_name/1`, `whereis_name/1`,
  and `send/2`. An adapter for a library that already does, such as
  `Horde.Registry` or `:syn`, only builds the tuple and wraps its lookups;
  `Condukt.Sessions.Registry.Horde` is one such adapter.

  ## Child sessions

  The registry also records which sessions are children of which, for
  `Condukt.Sessions.children/1` and the aborts and stops that follow the
  link. A child calls `c:join_parent/2` once, from its own process, as it
  starts, and the link must go when that process exits. Sub-agents are
  linked too, though they are not registered under an id. An adapter built
  before these callbacks existed records no links, and `Condukt.Sessions`
  logs a warning as it starts it: `children/1` is empty, and aborting or
  stopping a session leaves its children alone.
  """

  @doc "The child that runs the registry, started under `:condukt`'s supervisor."
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  @doc "The `:via` tuple a session with this id is started under."
  @callback via(id :: String.t(), opts :: keyword()) :: {:via, module(), term()}

  @doc "The session's pid, wherever it runs, or `nil`."
  @callback whereis(id :: String.t(), opts :: keyword()) :: pid() | nil

  @doc "Every session id the registry sees, in no particular order."
  @callback list(opts :: keyword()) :: [String.t()]

  @doc """
  Records the calling process as a child of the session `parent`, until the
  process exits. Called once per process.
  """
  @callback join_parent(parent :: String.t(), opts :: keyword()) :: :ok

  @doc "The pids of the session `parent`'s running children, wherever the registry sees them."
  @callback children(parent :: String.t(), opts :: keyword()) :: [pid()]
end
