defmodule Condukt.SessionStore.Memory do
  @moduledoc """
  ETS-backed session store for restoring sessions within the current virtual
  machine.

  The table is owned by a supervised process rather than by whichever caller
  reaches it first, so it lives as long as the application does. See
  `Condukt.SessionStore.Memory.Table`.

  The default key is `{agent_module, cwd, id}`, which is shared state: two
  concurrent tests using the same agent in the same directory address the same
  entry. Pass an explicit `:key` (or a unique `:id`) to keep them apart.

  The journal lives in the same table under its own entry, so a session that
  crashed mid-run can be restarted in the same virtual machine and resumed.
  """

  @behaviour Condukt.SessionStore

  alias Condukt.SessionStore.Memory.Table
  alias Condukt.SessionStore.Snapshot

  @table __MODULE__

  @impl true
  def load(opts) do
    Table.table!()

    case :ets.lookup(@table, key(opts)) do
      [{_, %Snapshot{} = snapshot}] -> {:ok, snapshot}
      [] -> :not_found
    end
  end

  @impl true
  def save(%Snapshot{} = snapshot, opts) do
    Table.table!()
    true = :ets.insert(@table, {key(opts), snapshot})
    :ok
  end

  @impl true
  def clear(opts) do
    Table.table!()
    true = :ets.delete(@table, key(opts))
    :ok
  end

  @impl true
  def append_journal(records, opts) when is_list(records) do
    Table.table!()
    key = journal_key(opts)

    stored =
      case :ets.lookup(@table, key) do
        [{_, reversed}] -> reversed
        [] -> []
      end

    true = :ets.insert(@table, {key, Enum.reverse(records, stored)})
    :ok
  end

  @impl true
  def load_journal(opts) do
    Table.table!()

    case :ets.lookup(@table, journal_key(opts)) do
      [{_, reversed}] -> {:ok, Enum.reverse(reversed)}
      [] -> {:ok, []}
    end
  end

  @impl true
  def clear_journal(opts) do
    Table.table!()
    true = :ets.delete(@table, journal_key(opts))
    :ok
  end

  # Tagged so a caller-chosen `:key` can never collide with a journal entry.
  defp journal_key(opts), do: {__MODULE__.Journal, key(opts)}

  defp key(opts) do
    Keyword.get_lazy(opts, :key, fn ->
      {
        Keyword.get(opts, :agent_module),
        Keyword.get(opts, :cwd),
        Keyword.get(opts, :id)
      }
    end)
  end
end
