defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.Repo

  def delete_expired(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    select_query =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
        order_by: e.id,
        limit: 10_000,
        select: e
      )

    expired_entries = Repo.all(select_query)

    if Enum.empty?(expired_entries) do
      {[], 0}
    else
      ids_to_delete = Enum.map(expired_entries, & &1.id)

      delete_query =
        from(e in KeyValueEntry,
          where: e.id in ^ids_to_delete
        )

      {count, _} = Repo.delete_all(delete_query)
      {expired_entries, count}
    end
  end
end
