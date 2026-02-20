defmodule TuistWeb.Plugs.SlackWebhookPlug do
  @moduledoc """
  Webhook plug for Slack event subscriptions with signature verification.

  Slack signs requests with `v0={hmac_sha256(signing_secret, "v0:{timestamp}:{body}")}`.
  This plug verifies that signature and rejects stale timestamps (> 5 minutes).

  It also handles `url_verification` challenges inline, echoing back the challenge token
  after request verification.
  """

  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.Plugs.WebhookPlug.CacheBodyReader

  require Logger

  @max_timestamp_age_seconds 300

  @impl true
  def init(options) do
    parser_opts =
      Plug.Parsers.init(
        parsers: [:json],
        body_reader: {CacheBodyReader, :read_body, []},
        json_decoder: Phoenix.json_library()
      )

    Keyword.put(options, :parser_opts, parser_opts)
  end

  @impl true
  def call(conn, options) do
    path = options[:at]

    case conn.request_path do
      ^path -> handle_webhook(conn, options)
      _ -> conn
    end
  end

  defp handle_webhook(conn, options) do
    secret = parse_secret!(options[:secret])
    parser_opts = options[:parser_opts]

    conn =
      try do
        Plug.Parsers.call(conn, parser_opts)
      rescue
        error in Bandit.HTTPError ->
          if error.plug_status == :request_timeout do
            conn
            |> send_resp(408, "Request Timeout")
            |> halt()
          else
            reraise error, __STACKTRACE__
          end
      end

    if conn.halted do
      conn
    else
      verify_and_dispatch(conn, secret, options)
    end
  end

  defp verify_and_dispatch(conn, secret, options) do
    module = options[:handler]
    timestamp = conn |> get_req_header("x-slack-request-timestamp") |> List.first()
    signature = conn |> get_req_header("x-slack-signature") |> List.first()

    cond do
      is_nil(signature) or is_nil(timestamp) ->
        conn
        |> send_resp(401, "Missing Slack signature headers")
        |> halt()

      timestamp_stale?(timestamp) ->
        conn
        |> send_resp(403, "Stale timestamp")
        |> halt()

      true ->
        raw_body =
          conn.assigns[:raw_body]
          |> List.wrap()
          |> IO.iodata_to_binary()

        expected = compute_signature(secret, timestamp, raw_body)

        if Plug.Crypto.secure_compare(signature, expected) do
          handle_verified_webhook(conn, module)
        else
          conn
          |> send_resp(403, "Invalid signature")
          |> halt()
        end
    end
  end

  defp handle_verified_webhook(conn, module) do
    case conn.body_params do
      %{"type" => "url_verification", "challenge" => challenge} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, challenge)
        |> halt()

      _ ->
        result_conn = module.handle(conn, conn.body_params)

        if result_conn.status do
          result_conn
        else
          result_conn |> send_resp(200, "OK") |> halt()
        end
    end
  end

  defp compute_signature(secret, timestamp, body) do
    basestring = "v0:#{timestamp}:#{body}"

    sig =
      :hmac
      |> :crypto.mac(:sha256, secret, basestring)
      |> Base.encode16(case: :lower)

    "v0=#{sig}"
  end

  defp timestamp_stale?(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {ts, ""} ->
        now = System.system_time(:second)
        abs(now - ts) > @max_timestamp_age_seconds

      _ ->
        true
    end
  end

  defp parse_secret!({m, f, a}), do: apply(m, f, a)
  defp parse_secret!(fun) when is_function(fun), do: fun.()
  defp parse_secret!(secret) when is_binary(secret), do: secret
end
