defmodule Cache.Registry.SyncCursor do
  @moduledoc false

  require Logger

  @key "registry/state/sync_cursor.json"

  def get do
    bucket = bucket()

    case bucket
         |> ExAws.S3.get_object(@key)
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"cursor" => cursor}} when is_integer(cursor) and cursor >= 0 -> cursor
          _ -> 0
        end

      {:error, {:http_error, 404, _}} ->
        0

      {:error, reason} ->
        Logger.warning("Failed to read registry sync cursor: #{inspect(reason)}")
        0
    end
  end

  def put(cursor) when is_integer(cursor) and cursor >= 0 do
    body =
      Jason.encode!(%{
        cursor: cursor,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case bucket()
         |> ExAws.S3.put_object(@key, body, content_type: "application/json")
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist registry sync cursor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp bucket, do: Application.get_env(:cache, :s3)[:bucket]
end
