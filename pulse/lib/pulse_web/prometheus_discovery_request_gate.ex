defmodule PulseWeb.PrometheusDiscoveryRequestGate do
  @moduledoc false
  import Plug.Conn

  alias Plug.Conn.InvalidHeaderError
  alias Plug.Conn.InvalidQueryError
  alias Plug.Conn.Query
  alias Plug.Conn.Utils

  @limit 32_768
  def init(opts), do: opts

  def call(conn, _opts) do
    if discovery_path?(Enum.map(conn.path_info, &URI.decode/1)) do
      cond do
        byte_size(conn.query_string) > @limit -> reject(conn, 414, "Discovery query string is too large.")
        conn.method == "POST" -> read_form(conn)
        true -> conn
      end
    else
      conn
    end
  end

  # Match the router's decoded path segments, not raw URL spelling. Encoded
  # segments and trailing slashes must not bypass the form budget/duplicate gate.
  defp discovery_path?(["api", "v1", route]) when route in ["labels", "series"], do: true
  defp discovery_path?(["api", "v1", "label", _name, "values"]), do: true
  defp discovery_path?(["loki", "api", "v1", route]) when route in ["labels", "series"], do: true
  defp discovery_path?(["loki", "api", "v1", "label", _name, "values"]), do: true
  defp discovery_path?(_), do: false

  defp read_form(conn) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "application", "x-www-form-urlencoded", _} <- Utils.media_type(type),
         encoding when encoding in [[], ["identity"]] <- get_req_header(conn, "content-encoding") do
      case read_body(conn, length: @limit, read_length: @limit, read_timeout: 5000) do
        {:ok, body, conn} when byte_size(body) <= @limit -> parse(conn, body)
        {:ok, _body, conn} -> reject(conn, 413, "Discovery form is too large.")
        {:more, _body, conn} -> reject(conn, 413, "Discovery form is too large.")
        {:error, _} -> reject(conn, 400, "Unable to read discovery form.")
      end
    else
      _ -> reject(conn, 415, "POST requires an uncompressed application/x-www-form-urlencoded body.")
    end
  end

  defp parse(conn, body) do
    # Preserve raw pairs for duplicate-scalar checks. Plug.Parsers sees the
    # already fetched body_params and does not read the socket a second time.
    %{conn | body_params: Query.decode(body)}
    |> assign(:prometheus_discovery_form, body)
  rescue
    _ in [InvalidQueryError, InvalidHeaderError, ArgumentError] ->
      reject(conn, 400, "Invalid discovery form.")
  end

  defp reject(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Pulse.JSON.encode!(%{"status" => "error", "errorType" => "bad_data", "error" => message}))
    |> halt()
  end
end
