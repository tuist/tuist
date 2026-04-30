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
          cache_endpoint: Map.get(event, :cache_endpoint, default_cache_endpoint()),
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(DownloadEvent, entries)
  end

  def track_download(%{scope: _, name: _, version: _} = event) do
    create_download_events([event])
  end

  defp default_cache_endpoint do
    case System.get_env("TUIST_REGISTRY_SERVING_REGION") do
      region when is_binary(region) and region != "" -> region
      _ -> node() |> to_string() |> String.split("@") |> List.last() |> to_string()
    end
  end
end
