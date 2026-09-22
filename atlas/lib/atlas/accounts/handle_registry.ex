defmodule Atlas.Accounts.HandleRegistry do
  @moduledoc """
  Authoritative in-process snapshot of the `handle -> account`
  mapping. Backs the error-ingest hot path so resolving a Sentry
  event's `auth_account_handle` costs a single `:persistent_term`
  read instead of a Postgres roundtrip per event.

  The registry loads every `account_handles` row at boot, keeps them
  in `:persistent_term`, and patches the snapshot in place when
  `Atlas.Accounts` broadcasts an insert/update/delete on the
  `"atlas:account_handles"` PubSub topic. Reads are lock-free and
  wait-free; writes are rare, and the module tolerates arbitrary
  `:reload` requests to fall back to a full reload when a broadcast
  is missed or the payload cannot be applied incrementally.

  ## Return shape

  `lookup/1` returns `{:ok, %{account_id, account_key, name,
  primary_domain, plan_tier}} | :error`. Only fields the error UI +
  Slack alerts care about are denormalised into the snapshot to keep
  it small (order of thousands of rows × a handful of strings).
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Repo

  require Logger

  @topic "atlas:account_handles"
  @persistent_key {__MODULE__, :snapshot}
  @empty_snapshot %{}

  def topic, do: @topic

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Resolves a Tuist handle (organisation or user) to the Atlas CRM
  account that owns it, or returns `:error` when the handle is not
  attributed to any account.
  """
  def lookup(handle) when is_binary(handle) do
    snapshot = current_snapshot()

    case Map.fetch(snapshot, normalise(handle)) do
      {:ok, entry} -> {:ok, entry}
      :error -> :error
    end
  end

  def lookup(_handle), do: :error

  @doc """
  Broadcasts an account-handle change so every node with a running
  registry patches its snapshot. Called from `Atlas.Accounts` after
  successful writes; also safe to call from tests to prime state.
  """
  def broadcast_change(payload) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, {:account_handle_changed, payload})
  end

  @doc """
  Forces a full reload from Postgres. Reserved for tests and for
  operational recovery — the PubSub incremental path handles the
  steady-state case.
  """
  def reload(server \\ __MODULE__), do: GenServer.call(server, :reload)

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(Atlas.PubSub, @topic)
    put_snapshot(load_snapshot())
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    put_snapshot(load_snapshot())
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:account_handle_changed, payload}, state) do
    apply_change(payload)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  ## Snapshot helpers

  defp current_snapshot do
    :persistent_term.get(@persistent_key, @empty_snapshot)
  end

  defp put_snapshot(snapshot) when is_map(snapshot) do
    :persistent_term.put(@persistent_key, snapshot)
  end

  # Full load from Postgres. Executed at boot and on explicit reload.
  # Fetches only the fields the UI + Slack renderers need.
  defp load_snapshot do
    query =
      from h in AccountHandle,
        join: a in Account,
        on: a.id == h.account_id,
        select:
          {h.handle,
           %{
             account_id: a.id,
             account_key: a.account_key,
             name: a.name,
             primary_domain: a.primary_domain,
             plan_tier: a.plan_tier
           }}

    query
    |> Repo.all()
    |> Map.new(fn {handle, entry} -> {normalise(handle), entry} end)
  rescue
    error ->
      Logger.warning("handle_registry: full reload failed, keeping previous snapshot: #{inspect(error)}")
      current_snapshot()
  end

  # Incremental patch. `:upsert` needs the handle + account_id +
  # denormalised account fields; `:delete` needs the handle. On
  # anything unexpected fall back to a full reload to stay coherent.
  defp apply_change(%{action: :upsert, handle: handle, entry: entry}) when is_binary(handle) and is_map(entry) do
    put_snapshot(Map.put(current_snapshot(), normalise(handle), entry))
  end

  defp apply_change(%{action: :delete, handle: handle}) when is_binary(handle) do
    put_snapshot(Map.delete(current_snapshot(), normalise(handle)))
  end

  defp apply_change(%{action: :account_updated, account_id: account_id, entry: entry})
       when is_binary(account_id) and is_map(entry) do
    # An account row changed (e.g. plan_tier flipped). Rewrite every
    # snapshot entry that points at this account so the enterprise
    # ordering picks up the change without a full reload.
    updated =
      Enum.reduce(current_snapshot(), current_snapshot(), fn {handle, existing}, acc ->
        if existing.account_id == account_id do
          Map.put(acc, handle, Map.merge(existing, entry))
        else
          acc
        end
      end)

    put_snapshot(updated)
  end

  defp apply_change(_other) do
    put_snapshot(load_snapshot())
  end

  defp normalise(handle) when is_binary(handle) do
    handle |> String.trim() |> String.downcase()
  end
end
