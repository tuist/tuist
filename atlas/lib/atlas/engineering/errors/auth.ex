defmodule Atlas.Engineering.Errors.Auth do
  @moduledoc """
  Parses the `X-Sentry-Auth` header (or its query-string fallback) as
  documented at
  <https://develop.sentry.dev/sdk/overview/#authentication>.

  The header carries a comma-separated list of `key=value` pairs
  prefixed with `Sentry ` (case-insensitive). We only require
  `sentry_key`; `sentry_version` should be `7` and `sentry_client`
  is expected but not enforced.

  As a fallback for browsers or SDKs that cannot set arbitrary headers,
  the same fields may be passed as query parameters, and the envelope
  header may carry a full `dsn` string.
  """

  alias Plug.Conn.Unfetched

  def extract(conn) do
    with :error <- extract_from_header(conn),
         :error <- extract_from_query(conn) do
      {:error, :missing_key}
    end
  end

  def extract_from_dsn(dsn) when is_binary(dsn) do
    uri = URI.parse(dsn)

    case uri.userinfo do
      nil -> {:error, :missing_key}
      "" -> {:error, :missing_key}
      user -> {:ok, user |> String.split(":") |> List.first()}
    end
  end

  def extract_from_dsn(_), do: {:error, :missing_key}

  defp extract_from_header(conn) do
    case Plug.Conn.get_req_header(conn, "x-sentry-auth") do
      [header | _] -> parse_header(header)
      _ -> :error
    end
  end

  defp extract_from_query(%Plug.Conn{query_params: %Unfetched{}} = conn) do
    conn
    |> Plug.Conn.fetch_query_params()
    |> extract_from_query()
  end

  defp extract_from_query(conn) do
    case conn.query_params do
      %{"sentry_key" => key} when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> :error
    end
  end

  defp parse_header(header) do
    header
    |> String.replace_prefix("Sentry ", "")
    |> String.replace_prefix("sentry ", "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(:error, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        ["sentry_key", value] -> {:ok, String.trim(value, "\"")}
        _ -> acc
      end
    end)
  end
end
