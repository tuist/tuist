defmodule PulseWeb.Authenticate do
  @moduledoc """
  Header-only authentication before any request body is read or parsed.

    * A Tuist-issued credential (`Pulse.Auth.Issuer`) is verified once and
      stored on the conn for `Pulse.Auth.verify/3`. When the request names no
      tenant, the credential's tenant becomes `X-Scope-OrgID`, so every route
      resolves tenancy from the credential rather than defaulting.
    * OTLP/HTTP exports are authorized before `Plug.Parsers` decodes JSON
      bodies, so unauthenticated callers cannot spend decode work.
    * With an issuer configured, `POST /mcp` requires a credential at the HTTP
      layer and answers OAuth 2.0 protected-resource challenges (RFC 9728) so
      MCP clients can discover the authorization server.
    * Ingest requests charge the tenant's quota from the issuer status list.
  """

  @behaviour Plug

  import Plug.Conn

  alias Pulse.Auth
  alias Pulse.Auth.Issuer
  alias Pulse.Auth.Quota
  alias Pulse.OTLP.Ingest
  alias Pulse.Storage.S3
  alias PulseWeb.OTLPHTTP

  @signals %{"logs" => :logs, "metrics" => :metrics, "traces" => :traces}
  @max_body_bytes 4 * 1024 * 1024

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = assign_principal(conn)

    case {conn.method, Enum.map(conn.path_info, &URI.decode/1)} do
      {"POST", ["v1", signal]} when is_map_key(@signals, signal) -> otlp(conn, @signals[signal])
      {"POST", ["mcp"]} -> mcp(conn)
      {"POST", ["loki", "api", "v1", "push"]} -> quota(conn, &json_error/3)
      {"POST", ["api", "v1", "write"]} -> quota(conn, &json_error/3)
      _ -> conn
    end
  end

  @doc "Verifies an issuer credential on `conn` once and names its tenant when the request does not."
  def assign_principal(%Plug.Conn{private: %{pulse_issuer: _}} = conn), do: conn

  def assign_principal(conn) do
    case Issuer.from_conn(conn) do
      :none ->
        conn

      result ->
        conn = put_private(conn, :pulse_issuer, result)

        case {result, get_req_header(conn, "x-scope-orgid")} do
          {{:ok, %{tenant: tenant}}, header} when header in [[], [""]] ->
            put_req_header(conn, "x-scope-orgid", tenant)

          {{:error, {:expired, %{tenant: tenant}}}, header} when header in [[], [""]] ->
            put_req_header(conn, "x-scope-orgid", tenant)

          _ ->
            conn
        end
    end
  end

  @doc "Charges `bytes` to the quota of the issuer principal on `conn`, if any."
  def charge_quota(conn, bytes) do
    case conn.private[:pulse_issuer] do
      {:ok, %{tenant: tenant, scopes: scopes}} -> if "ingest" in scopes, do: Quota.charge(tenant, bytes), else: :ok
      _ -> :ok
    end
  end

  defp otlp(conn, signal) do
    result =
      with {:ok, tenant} <- OTLPHTTP.single_header(conn, "x-scope-orgid", "default"),
           :ok <- S3.validate_tenant(tenant),
           do: Auth.verify(conn, tenant, :ingest)

    case result do
      :ok ->
        quota(conn, fn conn, status, message -> conn |> OTLPHTTP.error(status, message) |> halt() end)

      {:error, reason} ->
        {status, message} = Ingest.classify(signal, reason)
        conn = if status == 503, do: put_resp_header(conn, "retry-after", "1"), else: conn
        conn |> OTLPHTTP.error(status, message) |> halt()
    end
  end

  # Chunked requests without a length are charged the largest accepted body.
  defp quota(conn, error) do
    bytes =
      case get_req_header(conn, "content-length") do
        [value] ->
          case Integer.parse(value) do
            {length, ""} when length >= 0 -> min(length, @max_body_bytes)
            _ -> @max_body_bytes
          end

        _ ->
          @max_body_bytes
      end

    case charge_quota(conn, bytes) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn |> put_resp_header("retry-after", "10") |> error.(429, "tenant ingest quota exceeded")
    end
  end

  defp json_error(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Pulse.JSON.encode!(%{error: message}))
    |> halt()
  end

  defp mcp(conn) do
    case Issuer.config() do
      nil -> conn
      config -> mcp(conn, config, Auth.issuer_principal(conn))
    end
  end

  # Other credential kinds (tenant tokens, workload identity) are checked per
  # tool call as before.
  defp mcp(conn, config, :none) do
    if get_req_header(conn, "authorization") == [], do: challenge(conn, config, 401, nil), else: conn
  end

  defp mcp(conn, config, {:ok, %{scopes: scopes}}) do
    if "read" in scopes or Enum.any?(scopes, &String.starts_with?(&1, "alert:")),
      do: conn,
      else: challenge(conn, config, 403, "insufficient_scope")
  end

  defp mcp(conn, _config, {:error, :auth_unavailable}),
    do: conn |> put_resp_header("retry-after", "1") |> json_error(503, "auth_unavailable")

  defp mcp(conn, _config, {:error, :forbidden}), do: json_error(conn, 403, "forbidden")
  defp mcp(conn, config, {:error, _}), do: challenge(conn, config, 401, "invalid_token")

  defp challenge(conn, config, status, error) do
    params =
      [
        ~s(resource_metadata="#{config.audience}/.well-known/oauth-protected-resource/mcp"),
        ~s(scope="read"),
        error && ~s(error="#{error}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    conn
    |> put_resp_header("www-authenticate", "Bearer " <> params)
    |> json_error(status, error || "missing_token")
  end
end
