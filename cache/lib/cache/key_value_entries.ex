defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.Repo

  def delete_expired(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    ids_to_delete =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
        limit: 10_000,
        select: e.id
      )

    Repo.delete_all(from(e in KeyValueEntry, where: e.id in subquery(ids_to_delete)))
  end
end
