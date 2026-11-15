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
  """

  @doc "The child that runs the registry, started under `:condukt`'s supervisor."
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  @doc "The `:via` tuple a session with this id is started under."
  @callback via(id :: String.t(), opts :: keyword()) :: {:via, module(), term()}

  @doc "The session's pid, wherever it runs, or `nil`."
  @callback whereis(id :: String.t(), opts :: keyword()) :: pid() | nil

  @doc "Every session id the registry sees, in no particular order."
  @callback list(opts :: keyword()) :: [String.t()]
end
