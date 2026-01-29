defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  alias Tuist.Cache.CASEvent
  alias Tuist.IngestRepo

  @doc """
  Creates multiple CAS analytics events in a batch.

  ## Examples

      iex> create_cas_events([%{action: "upload", size: 1024, cas_id: "abc123", project_id: 1}, ...])
      {:ok, 2}
  """
  def create_cas_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          action: event.action,
          size: event.size,
          cas_id: event.cas_id,
          project_id: event.project_id,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(CASEvent, entries)
  end
end
