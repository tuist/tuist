defmodule PulseWeb.SentryBody do
  @moduledoc "Preserve raw Sentry bodies and bounded pixel query data before form/JSON parsers."
  @behaviour Plug

  import Plug.Conn

  alias Plug.Parsers.RequestTooLargeError

  def init(opts), do: opts

  def call(conn, _opts) do
    case Enum.map(conn.path_info, &URI.decode/1) do
      ["api", "store"] -> prepare(conn, "store")
      ["api", _project, endpoint] when endpoint in ["envelope", "store"] -> prepare(conn, endpoint)
      _ -> conn
    end
  end

  defp prepare(conn, endpoint) do
    conn =
      conn
      |> put_resp_header("cross-origin-resource-policy", "cross-origin")
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "POST")
      |> put_resp_header(
        "access-control-allow-headers",
        "content-type, content-encoding, authorization, x-sentry-auth, sentry-trace, baggage"
      )
      |> put_resp_header("access-control-expose-headers", "x-pulse-discarded-items, retry-after")

    case conn.method do
      "OPTIONS" ->
        conn |> send_resp(204, "") |> halt()

      "POST" ->
        # Credentials outside the body are checked before reading it; only a
        # DSN carried in the envelope header needs the body first.
        if Pulse.Sentry.request_credentials?(conn) and
             match?({:error, _}, Pulse.Sentry.authorize(conn, project(conn), %{})),
           do: error(conn, 403, "invalid_sentry_key"),
           else: read(conn)

      "GET" when endpoint == "store" ->
        conn = conn |> put_resp_header("cache-control", "no-store") |> fetch_query_params()
        put_private(conn, :sentry_body, conn.query_params["sentry_data"])

      "HEAD" when endpoint == "store" ->
        # Reject before Plug.Head rewrites probes to an ingesting GET.
        conn |> put_resp_header("allow", "GET, POST, OPTIONS") |> error(405, "method_not_allowed")

      _ ->
        conn
    end
  end

  defp project(conn) do
    case Enum.map(conn.path_info, &URI.decode/1) do
      ["api", project, _endpoint] -> project
      _ -> nil
    end
  end

  defp read(conn) do
    if get_req_header(conn, "content-encoding") in [[], [""], ["identity"], ["gzip"], ["deflate"], ["zstd"]] do
      case PulseWeb.CompressedBodyReader.read_body(conn, length: 4 * 1024 * 1024, deflate: true, zstd: true) do
        {:ok, body, conn} ->
          # Plug.Parsers skips a fetched body, regardless of its media type.
          conn |> Map.put(:body_params, %{}) |> put_private(:sentry_body, body)

        {:more, _, conn} ->
          error(conn, 413, "payload_too_large")

        {:error, _} ->
          error(conn, 400, "invalid_body")
      end
    else
      error(conn, 415, "unsupported_content_encoding")
    end
  rescue
    RequestTooLargeError -> error(conn, 413, "payload_too_large")
  end

  defp error(conn, status, reason) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Pulse.JSON.encode!(%{error: reason}))
    |> halt()
  end
end
