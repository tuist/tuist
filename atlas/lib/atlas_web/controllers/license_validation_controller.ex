defmodule AtlasWeb.LicenseValidationController do
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Licenses
  alias Atlas.Licenses.RateLimiter

  def create(conn, %{"meta" => %{"key" => key}}) when is_binary(key) do
    result =
      with :ok <- RateLimiter.check(validation_client_identifier(conn)) do
        Audit.with_context(%{interface: "api"}, fn ->
          Licenses.validate_online_key(key)
        end)
      end

    case result do
      {:ok, payload} ->
        json(conn, payload)

      {:error, retry_after_seconds} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> json(%{error: "rate limit exceeded"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "meta.key is required"})
  end

  defp validation_client_identifier(conn) do
    address =
      case get_req_header(conn, "x-real-ip") do
        [address | _rest] when address != "" -> String.trim(address)
        _other -> remote_ip_string(conn.remote_ip)
      end

    :crypto.hash(:sha256, "license-validation-client:" <> address)
  end

  defp remote_ip_string(address) when is_tuple(address) do
    case :inet.ntoa(address) do
      {:error, _reason} -> "unknown"
      address -> to_string(address)
    end
  end

  defp remote_ip_string(_address), do: "unknown"
end
