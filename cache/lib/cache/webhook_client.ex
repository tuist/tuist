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
    if Cache.AnalyticsCircuitBreaker.allow_request?(url) do
      do_request(secret, url, body, log_label)
    else
      :ok
    end
  end

  defp do_request(secret, url, body, log_label) do
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

    request =
      [
        url: url,
        method: :post,
        headers: headers,
        body: body,
        finch: Cache.Finch,
        retry: false,
        cache: false,
        receive_timeout: Cache.Config.analytics_receive_timeout_ms(),
        pool_timeout: Cache.Config.analytics_pool_timeout_ms()
      ]
      |> Keyword.merge(req_options)
      |> Req.new()
      |> ReqFuse.attach(Cache.AnalyticsCircuitBreaker.req_fuse_options(url))

    case Req.request(request) do
      {:ok, %{status: status}} when status in 200..299 ->
        Cache.AnalyticsCircuitBreaker.record_success(url)
        :ok

      {:ok, %{status: status} = response} ->
        if Cache.AnalyticsCircuitBreaker.melt?(response) do
          Cache.AnalyticsCircuitBreaker.record_failure(url, log_label, "status #{status}")
        end

        resp_body = Map.get(response, :body)
        Logger.error("Failed to send #{log_label} (status #{status}): #{inspect(resp_body)}")
        :ok

      {:error, %RuntimeError{message: "circuit breaker is open"}} ->
        :ok

      {:error, reason} ->
        if Cache.AnalyticsCircuitBreaker.melt?({:error, reason}) do
          Cache.AnalyticsCircuitBreaker.record_failure(url, log_label, inspect(reason))
        end

        Logger.error("Failed to send #{log_label}: #{inspect(reason)}")
        :ok
    end
  end
end
