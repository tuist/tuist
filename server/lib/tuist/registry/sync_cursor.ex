defmodule Tuist.Registry.SyncCursor do
  @moduledoc false

  alias Tuist.Registry.Storage

  require Logger

  @key "registry/state/sync_cursor.json"

  def get do
    case Storage.get_object(@key) do
      {:ok, body, _etag} ->
        case JSON.decode(body) do
          {:ok, %{"cursor" => cursor}} when is_integer(cursor) and cursor >= 0 -> cursor
          _ -> 0
        end

      {:error, :not_found} ->
        0

      {:error, reason} ->
        Logger.warning("Failed to read registry sync cursor: #{inspect(reason)}")
        0
    end
  end

  def put(cursor) when is_integer(cursor) and cursor >= 0 do
    body =
      JSON.encode!(%{
        cursor: cursor,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case Storage.put_object(@key, body, content_type: "application/json") do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist registry sync cursor: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
