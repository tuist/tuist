defmodule Tuist.Registry do
  @moduledoc false
  alias Tuist.IngestRepo
  alias Tuist.Registry.DownloadEvent

  def create_download_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          scope: event.scope,
          name: event.name,
          version: event.version,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(DownloadEvent, entries)
  end
end
