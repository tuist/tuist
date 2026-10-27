defmodule Atlas.Grafana.Loki do
  @moduledoc """
  Read-only client for the Grafana Cloud Loki tenant that stores Tuist logs.

  Atlas uses this client only for account-level product-usage aggregation. It
  authenticates with a dedicated Grafana access-policy token rather than a
  person's Model Context Protocol connection.
  """

  require Logger

  @default_receive_timeout 30_000
  @lookback_days 8

  @doc """
  Return Model Context Protocol usage for one Tuist account handle.

  The counts include successful tool responses from the last 24 hours and
  seven days. `last_used_at` is the newest matching request within the same
  bounded eight-day scan used by the feature-usage collector.
  """
  def mcp_usage(account_handle, opts \\ []) when is_binary(account_handle) do
    client = client(opts)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with :ok <- validate_client(client),
         {:ok, events_last_24h} <- count(client, account_handle, "24h", now),
         {:ok, events_last_7d} <- count(client, account_handle, "7d", now),
         {:ok, last_used_at} <- latest(client, account_handle, now) do
      {:ok,
       %{
         events_last_24h: events_last_24h,
         events_last_7d: events_last_7d,
         events_prior_7d: 0,
         last_used_at: last_used_at
       }}
    end
  end

  @doc """
  Whether the Grafana Cloud log-query credentials are configured.
  """
  def configured?(opts \\ []) do
    client = client(opts)
    present?(client.base_url) and present?(client.username) and present?(client.token)
  end

  defp count(client, account_handle, window, now) do
    query = "sum(count_over_time(#{mcp_log_query(account_handle)}[#{window}])) or on() vector(0)"

    case request(client, "/loki/api/v1/query", query: query, time: timestamp(now)) do
      {:ok, body} -> {:ok, count_from_response(body)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp latest(client, account_handle, now) do
    start = now |> DateTime.add(-@lookback_days * 86_400, :second) |> timestamp()

    case request(client, "/loki/api/v1/query_range",
           query: mcp_log_query(account_handle),
           start: start,
           end: timestamp(now),
           limit: 1,
           direction: "backward"
         ) do
      {:ok, body} -> {:ok, latest_from_response(body)}
      {:error, reason} -> {:error, reason}
    end
  end

  # The production Pod-log stream supplies `service_name`, `env`, and
  # `container` labels. The three Model Context Protocol fields are printed by
  # Logger as logfmt metadata, so they are queried after parsing the line rather
  # than promoted to high-cardinality Loki labels.
  defp mcp_log_query(account_handle) do
    account_handle = Jason.encode!(account_handle)

    ~s({service_name="tuist-server", env="production", container="server"} | logfmt | mcp_account_handle = #{account_handle} | mcp_tool_name != "")
  end

  defp request(client, path, params) do
    request =
      Req.new(
        method: :get,
        url: client.base_url <> path,
        auth: {:basic, client.username, client.token},
        receive_timeout: client.receive_timeout,
        headers: [{"accept", "application/json"}],
        params: params
      )

    case client.request.(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Grafana Loki usage query failed: status=#{status}")
        {:error, "Grafana Loki usage query failed."}

      {:error, reason} ->
        Logger.warning("Grafana Loki usage query failed: #{inspect(reason)}")
        {:error, "Could not reach Grafana Loki."}
    end
  end

  defp count_from_response(%{"data" => %{"result" => [%{"value" => [_timestamp, value]} | _]}}), do: to_integer(value)

  defp count_from_response(_response), do: 0

  defp latest_from_response(%{"data" => %{"result" => [%{"values" => [[timestamp | _] | _]} | _]}}),
    do: to_datetime(timestamp)

  defp latest_from_response(_response), do: nil

  defp timestamp(datetime), do: datetime |> DateTime.to_unix(:nanosecond) |> Integer.to_string()

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> 0
    end
  end

  defp to_integer(_value), do: 0

  defp to_datetime(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp, :nanosecond) do
      {:ok, datetime} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp to_datetime(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {integer, ""} -> to_datetime(integer)
      _ -> nil
    end
  end

  defp to_datetime(_timestamp), do: nil

  defp validate_client(client) do
    if present?(client.base_url) and present?(client.username) and present?(client.token) do
      :ok
    else
      {:error, "Grafana Loki usage queries are not configured."}
    end
  end

  defp client(opts) do
    config = config()

    %{
      base_url: base_url(configured_option(opts, config, :base_url)),
      username: configured_option(opts, config, :username),
      token: configured_option(opts, config, :token),
      receive_timeout: receive_timeout(configured_option(opts, config, :receive_timeout)),
      request: Keyword.get(opts, :request, &Req.request/1)
    }
  end

  defp configured_option(opts, config, key) do
    if Keyword.has_key?(opts, key), do: Keyword.get(opts, key), else: Keyword.get(config, key)
  end

  defp base_url(value) when is_binary(value) and value != "", do: String.trim_trailing(value, "/")
  defp base_url(_value), do: nil

  defp receive_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp receive_timeout(_timeout), do: @default_receive_timeout

  defp present?(value), do: is_binary(value) and value != ""

  defp config, do: Application.get_env(:atlas, :grafana_loki, [])
end
