defmodule TuistWeb.Plugs.SlackWebhookPlug do
  @moduledoc """
  Verifies an inbound Slack webhook against the Slack signing scheme
  (`v0:<unix_timestamp>:<raw_body>` HMAC-SHA256, hex, sent as
  `X-Slack-Signature: v0=<hex>` plus `X-Slack-Request-Timestamp`).
  Bounds replay via a 5-minute tolerance on the timestamp.

  Mirrors `TuistWeb.Plugs.WebhookPlug`'s shape so it composes the
  same way in endpoint.ex: matches a single `at:` path, caches the
  raw body via a body reader so the HMAC can be computed after
  `Plug.Parsers` has consumed it, then calls `handler.action(conn,
  body_params)` on success.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @signature_header "x-slack-signature"
  @timestamp_header "x-slack-request-timestamp"
  @timestamp_tolerance_seconds 300
  @signature_version "v0"

  defmodule CacheBodyReader do
    @moduledoc false

    def read_body(conn, opts) do
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} -> {:ok, body, cache(conn, body)}
        {:more, body, conn} -> {:more, body, cache(conn, body)}
        {:error, reason} -> {:error, reason}
      end
    end

    defp cache(conn, body) do
      update_in(conn.assigns[:raw_body], fn
        nil -> body
        existing -> [existing, body]
      end)
    end
  end

  @impl true
  def init(options) do
    parser_options = [
      parsers: [:urlencoded, :json],
      body_reader: {CacheBodyReader, :read_body, []},
      json_decoder: Phoenix.json_library(),
      length: Keyword.get(options, :body_length, 1_048_576),
      read_timeout: Keyword.get(options, :read_timeout, 5_000)
    ]

    Keyword.put(options, :parser_opts, Plug.Parsers.init(parser_options))
  end

  @impl true
  def call(conn, options) do
    path = options[:at]

    if conn.request_path == path do
      handle(conn, options)
    else
      conn
    end
  end

  defp handle(conn, options) do
    with [signature] <- get_req_header(conn, @signature_header),
         [timestamp] <- get_req_header(conn, @timestamp_header) do
      conn = Plug.Parsers.call(conn, options[:parser_opts])

      if conn.halted do
        conn
      else
        verify_and_dispatch(conn, options, signature, timestamp)
      end
    else
      _ ->
        conn
        |> send_resp(401, "Missing Slack signature headers")
        |> halt()
    end
  rescue
    Plug.Parsers.RequestTooLargeError ->
      conn |> send_resp(413, "Payload Too Large") |> halt()
  end

  defp verify_and_dispatch(conn, options, signature, timestamp_str) do
    with {timestamp, ""} <- Integer.parse(timestamp_str),
         :ok <- check_timestamp(timestamp),
         {:ok, secret} <- resolve_secret(options[:secret]),
         true <- valid_signature?(conn, secret, signature, timestamp) do
      dispatch(conn, options)
    else
      _ ->
        conn |> send_resp(403, "Invalid Slack signature") |> halt()
    end
  end

  defp dispatch(conn, options) do
    module = options[:handler]
    action = options[:action] || :handle
    result = apply(module, action, [conn, conn.body_params])

    if result.status do
      result
    else
      result |> send_resp(200, "OK") |> halt()
    end
  end

  defp check_timestamp(ts) do
    now = System.system_time(:second)

    if abs(now - ts) <= @timestamp_tolerance_seconds do
      :ok
    else
      {:error, :timestamp_outside_tolerance}
    end
  end

  defp valid_signature?(conn, secret, signature, timestamp) do
    raw_body =
      conn.assigns
      |> Map.get(:raw_body, "")
      |> List.wrap()
      |> IO.iodata_to_binary()

    payload = "#{@signature_version}:#{timestamp}:#{raw_body}"
    expected_hex = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
    expected = "#{@signature_version}=#{expected_hex}"

    Plug.Crypto.secure_compare(signature, expected)
  end

  defp resolve_secret({m, f, a}), do: wrap(apply(m, f, a))
  defp resolve_secret(fun) when is_function(fun, 0), do: wrap(fun.())
  defp resolve_secret(secret) when is_binary(secret), do: {:ok, secret}
  defp resolve_secret(_), do: :error

  defp wrap(nil), do: :error
  defp wrap(""), do: :error
  defp wrap(secret) when is_binary(secret), do: {:ok, secret}
  defp wrap(_), do: :error
end
