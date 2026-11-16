defmodule Condukt.SessionStore do
  @moduledoc """
  Behaviour for persisting and restoring Condukt sessions.

  ## What this is, and what it is not

  A session store is a **snapshot cache**: it holds the latest state of one
  session so the same conversation can be picked up again. It is deliberately
  not a repository. There is no listing, no querying, no pagination, and no
  tenancy, and `save/2` replaces the whole snapshot rather than appending to it.

  That shape suits what it is for. It does not suit a product that holds many
  people's sessions and needs to ask questions about them, and growing this
  behaviour until it does would mean rewriting a conversation's entire history
  on every turn, which costs more the longer the conversation gets.

  A system that needs to list, search, or scope sessions should own its own
  persistence and use `Condukt.SessionStore` alongside it, or not at all. The
  pieces to build on are already here: `Condukt.SessionID` is time-ordered,
  `Condukt.SessionStore.Snapshot` is versioned and carries `:id` and `:actor`,
  and `Condukt.Notifier` reports events as they happen rather than after a save.

  ## The journal

  A snapshot is written once per run, so on its own it loses the run a process
  dies in. A store that also implements the optional journal callbacks,
  `append_journal/2`, `load_journal/1`, and `clear_journal/1`, makes that run
  durable without rewriting the history on every step: the session appends one
  small record per step (the run's prompt, each model response, each tool
  call's intent before it runs, each tool result) and only rewrites the
  snapshot when the run ends, after which it clears the journal.

  After a restart the session folds the journal into the snapshot it loaded and
  holds an unfinished run as interrupted, for the caller to continue with
  `Condukt.Session.resume/2`. See the Sessions and Persistence guide.

  A journaling store must keep records in the order they were appended and
  return them unchanged. The session serializes its own appends, so a store
  does not need to handle concurrent writers to one session's journal.
  `save/2` and `clear/1` must leave the journal alone, and `clear_journal/1`
  must leave the snapshot alone: the session decides when each is cleared.
  Records are opaque terms to the store, like snapshots.

  A journaling store is the session's durable record, so a session does not
  start when its snapshot or journal cannot be loaded (`{:error,
  {:snapshot_load_failed, reason}}` or `{:error, {:journal_load_failed,
  reason}}`) rather than starting over and later saving over what it could
  not read. A snapshot-only store is a cache: a failed load starts fresh.

  `Condukt.SessionStore.Conformance` holds the tests a store has to pass.

  ## Implementing one

  Condukt ships memory and disk-backed stores, and callers can provide their
  own. `Condukt.Session` passes `:agent_module`, `:cwd`, an optional `:id`, an
  optional stable `:key`, and any configured `:session_store_opts` to each
  callback.

  A store returns whatever term it was given back from `load/1`; the session
  passes it through `Condukt.SessionStore.Snapshot.migrate/1`, so a store never
  has to know which snapshot version it is holding.
  """

  @callback load(keyword()) :: {:ok, term()} | :not_found | {:error, term()}
  @callback save(term(), keyword()) :: :ok | {:error, term()}
  @callback clear(keyword()) :: :ok | {:error, term()}

  @doc "Appends journal records after the ones already stored, in order."
  @callback append_journal([term()], keyword()) :: :ok | {:error, term()}

  @doc "Returns every journal record in append order, or `{:ok, []}` when there are none."
  @callback load_journal(keyword()) :: {:ok, [term()]} | {:error, term()}

  @doc "Removes every journal record, leaving the snapshot in place."
  @callback clear_journal(keyword()) :: :ok | {:error, term()}

  @optional_callbacks append_journal: 2, load_journal: 1, clear_journal: 1

  def load(store, default_opts \\ [])

  def load({module, opts}, default_opts) do
    module.load(Keyword.merge(default_opts, opts))
  end

  def load(module, default_opts) when is_atom(module) do
    module.load(default_opts)
  end

  def save(store, snapshot, default_opts \\ [])

  def save({module, opts}, snapshot, default_opts) do
    module.save(snapshot, Keyword.merge(default_opts, opts))
  end

  def save(module, snapshot, default_opts) when is_atom(module) do
    module.save(snapshot, default_opts)
  end

  def clear(store, default_opts \\ [])

  def clear({module, opts}, default_opts) do
    module.clear(Keyword.merge(default_opts, opts))
  end

  def clear(module, default_opts) when is_atom(module) do
    module.clear(default_opts)
  end

  @doc "Whether a store implements the journal callbacks."
  def journal?({module, _opts}), do: journal?(module)

  def journal?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :append_journal, 2) and
      function_exported?(module, :load_journal, 1) and function_exported?(module, :clear_journal, 1)
  end

  def journal?(_store), do: false

  def append_journal(store, records, default_opts \\ []) do
    {module, opts} = split(store, default_opts)
    module.append_journal(records, opts)
  end

  def load_journal(store, default_opts \\ []) do
    {module, opts} = split(store, default_opts)
    module.load_journal(opts)
  end

  def clear_journal(store, default_opts \\ []) do
    {module, opts} = split(store, default_opts)
    module.clear_journal(opts)
  end

  defp split({module, opts}, default_opts), do: {module, Keyword.merge(default_opts, opts)}
  defp split(module, default_opts) when is_atom(module), do: {module, default_opts}
end
