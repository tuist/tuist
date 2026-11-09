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
end
