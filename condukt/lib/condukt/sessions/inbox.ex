defmodule Condukt.Sessions.Inbox do
  @moduledoc """
  Behaviour for storing input submitted to sessions by id.

  `Condukt.Sessions.submit/3` without an inbox reaches only a running session,
  and a session's queued input lives in its process. A host that runs several
  nodes, or stops idle sessions, configures an inbox instead. Every submission
  then goes through it, wherever the target session runs, or whether it runs
  at all:

    1. `c:put/2` stores the input, once per `{session_id, request_id}`. A retry
       with the same request id is answered `{:error, :duplicate}` and stored
       nowhere, so input is delivered at most once.
    2. A running target is told to take its stored input with `c:take/2`.
    3. When no node runs the target, a `Condukt.Sessions.Resumer` starts it,
       and a session with an inbox takes its stored input as it starts.

  An inbox is keyed by session id alone, because a sender knows nothing else
  about its target. Configure the same one on every node, before `:condukt`
  starts:

      config :condukt, inbox: {MyApp.SessionInbox, []}

  `Condukt.Sessions.start/2` and `Condukt.Sessions.submit/3` default to it,
  and both take an `:inbox` option that overrides it. Sessions started any
  other way use one only when given `:inbox`.

  `Condukt.Sessions.Inbox.Memory` keeps inputs in the local node's memory, for
  tests and single-node use.

  ## Implementing one

  Where inputs are kept is the implementation's business: a relational table,
  a key-value store, a log, files on a shared volume. What Condukt relies on is
  this contract, which `Condukt.Sessions.Inbox.Conformance` checks:

    * `c:put/2` stores the input if no input with the same
      `{session_id, request_id}` was ever put, and returns `:ok` only once it
      is stored where every node's `c:take/2` sees it. Otherwise it returns
      `{:error, :duplicate}`, including when that input was taken long ago.
      Keep keys at least as long as a sender may retry.
    * `c:take/2` returns the session's untaken inputs in the order they were
      put and marks them taken in the same step, so two concurrent takers,
      on any nodes, never both get one.
    * Inputs come back with every field as they were put. Each is plain data:
      strings, a boolean, and a `DateTime` whose precision may be reduced.

  Both callbacks may be called from any node, and from the session's own
  process, so they should not block for long.

  ## Delivery guarantees

  `c:put/2` is where an input is accepted, so a submission is delivered at
  most once however often it is retried, from any node. A session marks its
  inputs taken before they enter its queue, and its queue lives in its
  process: a session that crashes between taking an input and finishing the
  turn it started loses that input, and its sender hears nothing. A session
  that is aborted or stopped settles its inputs as `:aborted`. Senders that
  wait should park with a deadline.

  Closing that window is the durable session journal's job, not the inbox's:
  each turn started from an input carries the input's request id, which a
  journaling `Condukt.SessionStore` records with the turn it starts.
  """

  alias Condukt.Sessions.Input

  @doc "Stores `input` for `input.session_id`, unless its request id was put before."
  @callback put(input :: %Input{}, opts :: keyword()) :: :ok | {:error, :duplicate} | {:error, term()}

  @doc "Takes the session's untaken inputs, in the order they were put."
  @callback take(session_id :: String.t(), opts :: keyword()) :: {:ok, [%Input{}]} | {:error, term()}

  @doc false
  def default, do: Application.get_env(:condukt, :inbox)

  @doc false
  def put(inbox, %Input{} = input) do
    {module, opts} = normalize(inbox)
    module.put(input, opts)
  end

  @doc false
  def take(inbox, session_id) do
    {module, opts} = normalize(inbox)
    module.take(session_id, opts)
  end

  defp normalize({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize(module) when is_atom(module), do: {module, []}
end
