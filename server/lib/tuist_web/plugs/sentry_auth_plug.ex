defmodule TuistWeb.SentryAuthPlug do
  @moduledoc """
  Lets a Sentry SDK authenticate with a Tuist account token.

  Sentry SDKs cannot send an `Authorization` header: they send the DSN's key
  in `X-Sentry-Auth` (`Sentry sentry_key=...`), or as the `sentry_key` query
  parameter when they cannot set headers. A DSN whose key is an account token,
  such as `https://<token>@tuist.dev/api/accounts/<handle>/pulse/sentry/<service>/1`,
  therefore reaches the API with the token there. This plug presents that key
  as a bearer token so the ordinary authentication pipeline verifies it. A
  request that already has an `Authorization` header is left alone.

  Account tokens end in standard base64, whose `/`, `+` and `=` a DSN's
  userinfo must percent-encode, and SDKs send the key as written in the DSN,
  so the key is percent-decoded.

  Pipe it only ahead of authentication for Sentry ingestion routes.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with [] <- get_req_header(conn, "authorization"),
         key when is_binary(key) and key != "" <- sentry_key(conn) do
      put_req_header(conn, "authorization", "Bearer " <> URI.decode(key))
    else
      _ -> conn
    end
  end

  defp sentry_key(conn) do
    case get_req_header(conn, "x-sentry-auth") do
      [header | _] -> header_key(header)
      [] -> conn |> fetch_query_params() |> Map.get(:query_params) |> Map.get("sentry_key")
    end
  end

  defp header_key(header) do
    header
    |> String.trim()
    |> String.replace(~r/\Asentry\s+/i, "")
    |> String.split(",")
    |> Enum.find_value(fn field ->
      case field |> String.split("=", parts: 2) |> Enum.map(&String.trim/1) do
        ["sentry_key", value] -> String.trim(value, "\"")
        _ -> nil
      end
    end)
  end
end
