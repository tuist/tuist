defmodule Pulse.Auth do
  @moduledoc """
  Boundary for tenant authorization checks.

  `verify/3` is called from ingest and read paths before Pulse attributes a
  request to a tenant. Implementations (the `verify/2` callback) decide
  whether the caller is allowed to speak for the tenant they named; they do **not** decide which tenant a
  request belongs to (that is a routing concern, e.g. `X-Scope-OrgID`).

  After any credential verifies, `Pulse.Tenants.check/1` refuses tenants the
  registry marks suspended or deleted.

  Two implementations ship in-tree:

    * `Pulse.Auth.Open` — accepts everything. Default for dev and test.
    * `Pulse.Auth.SharedSecret` — requires an `Authorization: Bearer <token>`
      header that matches a per-tenant token from application env. Default
      for prod.

  `Pulse.Auth.WorkloadIdentity` additionally accepts Kubernetes projected
  ServiceAccount tokens bound to tenants and capabilities, alongside either
  module. `Pulse.Auth.Issuer` accepts credentials minted by one trusted issuer
  (Tuist in the hosted product), whose claims carry the tenant and scopes.

  The active implementation is read from `Runtime.get_env(:pulse,
  Pulse.Auth)[:module]` at call time so tests can swap it without
  recompiling.
  """

  alias Plug.Conn
  alias Pulse.Auth.Issuer
  alias Pulse.Auth.WorkloadIdentity
  alias Pulse.Runtime

  @type reason :: :missing_token | :invalid_token | :unknown_tenant | :forbidden | term()

  @callback verify(Conn.t(), tenant :: String.t()) :: :ok | {:error, reason()}

  @doc """
  Authorizes the request for `tenant` and `capability`: `:read` for query and
  MCP paths, `:ingest` for push/write paths.

  A Bearer JWT is verified by `Pulse.Auth.WorkloadIdentity` when workload
  identity trust is configured; its bindings decide the capability. Every other
  credential goes to the configured module, whose tenant tokens grant both
  capabilities as they always have.
  """
  @spec verify(Conn.t(), String.t(), WorkloadIdentity.capability()) :: :ok | {:error, reason()}
  def verify(conn, tenant, capability) when is_binary(tenant) and capability in [:read, :ingest] do
    verified =
      case issuer_principal(conn) do
        :none -> verify_configured(conn, tenant, capability)
        result -> Issuer.authorize(result, tenant, capability)
      end

    # Suspended and deleted tenants are refused whatever the credential.
    with :ok <- verified, do: Pulse.Tenants.check(tenant)
  end

  defp verify_configured(conn, tenant, capability) do
    with trust when trust != [] <- WorkloadIdentity.trust(),
         {:ok, token} <- bearer(conn),
         true <- WorkloadIdentity.jwt?(token) do
      WorkloadIdentity.verify(token, tenant, capability, trust)
    else
      _ -> module().verify(conn, tenant)
    end
  end

  @doc """
  The authentication result for a Tuist-issued credential on `conn`, or
  `:none` when the request carries no such credential. `PulseWeb.Authenticate`
  verifies it once before the body is read and stores it on the conn.
  """
  def issuer_principal(%Conn{private: %{pulse_issuer: result}}), do: result
  def issuer_principal(conn), do: Issuer.from_conn(conn)

  defp bearer(conn) do
    with [header] <- Conn.get_req_header(conn, "authorization"),
         [scheme, token] when token != "" <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      {:ok, token}
    end
  end

  @doc "Decoded HTTP Basic credentials, or `:error` when the request has none."
  @spec basic_credentials(Conn.t()) :: {:ok, String.t(), String.t()} | :error
  def basic_credentials(conn) do
    with [header] <- Conn.get_req_header(conn, "authorization"),
         [scheme, encoded] <- String.split(header, " ", parts: 2),
         "basic" <- String.downcase(scheme),
         {:ok, decoded} <- Base.decode64(String.trim(encoded)),
         [username, password] when username != "" and password != "" <- :binary.split(decoded, ":") do
      {:ok, username, password}
    else
      _ -> :error
    end
  end

  @spec module() :: module()
  def module do
    case Runtime.get_env(:pulse, __MODULE__) do
      nil ->
        raise """
        Pulse.Auth is not configured. This should never happen — config/config.exs
        sets `Pulse.Auth.Open` as the compile-time default. Refusing to accept
        traffic rather than fail open.
        """

      env ->
        case Keyword.get(env, :module) do
          nil ->
            raise "Pulse.Auth :module key is not set. See config/config.exs."

          :must_configure_at_runtime ->
            raise """
            Pulse.Auth is still set to the prod sentinel `:must_configure_at_runtime`.
            runtime.exs must set `config :pulse, Pulse.Auth, module: Pulse.Auth.SharedSecret, tokens: %{...}`
            before the app accepts traffic.
            """

          mod when is_atom(mod) ->
            mod
        end
    end
  end
end
