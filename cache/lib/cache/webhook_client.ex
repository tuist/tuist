defmodule Cache.WebhookClient do
  @moduledoc """
  Shared HTTP client for sending signed webhook requests to the server.

  Handles HMAC signature computation, header construction, and error logging
  for all event pipelines.
  """

  require Logger

  def signed_post(url, body, log_label) do
    case Cache.Config.api_key() do
      nil -> :ok
      secret -> do_signed_post(secret, url, body, log_label)
    end
  end

  defp do_signed_post(secret, url, body, log_label) do
    signature =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    headers = [
      {"x-cache-signature", signature},
      {"content-type", "application/json"},
      {"x-cache-endpoint", Cache.Config.cache_endpoint()}
    ]

    req_options = Application.get_env(:cache, :req_options, [])

    options =
      Keyword.merge(
        [
          url: url,
          method: :post,
          headers: headers,
          body: body,
          finch: Cache.Finch,
          retry: false,
          cache: false
        ],
        req_options
      )

    case Req.request(options) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Failed to send #{log_label} (status #{status}): #{inspect(resp_body)}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send #{log_label}: #{inspect(reason)}")
        :ok
    end
  end
end
