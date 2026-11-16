defmodule Tuist.Agents.Bucket do
  @moduledoc """
  The `Condukt.SessionStore.ObjectStore.Bucket` durable agent sessions live
  in: Tuist's own object storage bucket (`Tuist.Environment.s3_bucket_name/0`),
  through ExAws, so it uses the same endpoint, credentials, and connection
  pool as `Tuist.Storage`. It never uses an account's custom storage: a
  session is Tuist's working state, not the customer's artifact.

  Creates use `If-None-Match: *`, which Tigris and MinIO honour.
  """

  @behaviour Condukt.SessionStore.ObjectStore.Bucket

  @impl true
  def create(_config, key, body) do
    bucket()
    |> ExAws.S3.put_object(key, body, if_none_match: "*")
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, {:http_error, status, _}} when status in [409, 412] -> {:error, :exists}
      {:error, reason} -> {:error, reason(reason)}
    end
  end

  @impl true
  def get(_config, key) do
    case bucket() |> ExAws.S3.get_object(key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> :not_found
      {:error, reason} -> {:error, reason(reason)}
    end
  end

  @impl true
  def list(_config, prefix, start_after) do
    opts = if start_after, do: [prefix: prefix, start_after: start_after], else: [prefix: prefix]

    bucket()
    |> ExAws.S3.list_objects_v2(opts)
    |> ExAws.stream!()
    |> Enum.map(& &1.key)
    |> then(&{:ok, &1})
  rescue
    error -> {:error, {:list_failed, error.__struct__}}
  end

  @impl true
  def delete(_config, key) do
    case bucket() |> ExAws.S3.delete_object(key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, {:http_error, 404, _}} -> :ok
      {:error, reason} -> {:error, reason(reason)}
    end
  end

  defp bucket, do: Tuist.Environment.s3_bucket_name()

  # The session logs a failed write by its reason, so keep the response body,
  # which can echo the request, out of it.
  defp reason({:http_error, status, _response}), do: {:http, status}
  defp reason(reason), do: reason
end
