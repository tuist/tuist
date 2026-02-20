defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.Repo

  @doc """
  Deletes expired entries and returns them for downstream CAS cleanup.

  Uses a two-phase approach: SELECT expired entries first, then DELETE by ID
  with a re-check of the cutoff condition. An entry that gets accessed between
  the SELECT and the DELETE will survive the DELETE but still appear in the
  returned list — the CASCleanupWorker's reference check handles this safely.
  """
  def delete_expired(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    select_query =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
        order_by: e.id,
        limit: 10_000,
        select: e
      )

    case Repo.all(select_query) do
      [] ->
        {[], 0}

      expired_entries ->
        ids_to_delete = Enum.map(expired_entries, & &1.id)

        delete_query =
          from(e in KeyValueEntry,
            where: e.id in ^ids_to_delete,
            where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff
          )

        {count, _} = Repo.delete_all(delete_query)
        {expired_entries, count}
    end
  end

  def referenced_hashes(_account_handle, _project_handle, []), do: []

  def referenced_hashes(account_handle, project_handle, hashes) when is_list(hashes) do
    hash_set = MapSet.new(hashes)
    key_prefix = "keyvalue:#{escape_like(account_handle)}:#{escape_like(project_handle)}:%"

    from(e in KeyValueEntry,
      where: fragment("? LIKE ? ESCAPE '!'", e.key, ^key_prefix),
      select: e.json_payload
    )
    |> Repo.all()
    |> Enum.flat_map(fn payload ->
      case Jason.decode(payload) do
        {:ok, %{"entries" => entries}} when is_list(entries) ->
          entries
          |> Enum.map(&Map.get(&1, "value"))
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(hash_set, &1))
  end

  defp escape_like(str) do
    str
    |> String.replace("!", "!!")
    |> String.replace("%", "!%")
    |> String.replace("_", "!_")
  end
end
