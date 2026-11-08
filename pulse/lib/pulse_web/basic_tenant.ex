defmodule PulseWeb.BasicTenant do
  @moduledoc """
  Grafana Cloud-style tenancy for clients that only speak HTTP Basic auth.

  Alloy destinations, Prometheus remote write and Grafana datasources often
  send `Authorization: Basic <tenant>:<token>` instead of a bearer token and
  an `X-Scope-OrgID` header. When a request carries Basic credentials and no
  tenant header, this plug names the Basic username as the tenant, so every
  route resolves tenancy the same way. An explicit `X-Scope-OrgID` is never
  replaced; `Pulse.Auth.SharedSecret` then rejects Basic credentials whose
  username differs from it.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with [] <- get_req_header(conn, "x-scope-orgid"),
         {:ok, tenant, _password} <- Pulse.Auth.basic_credentials(conn) do
      %{conn | req_headers: [{"x-scope-orgid", tenant} | conn.req_headers]}
    else
      _ -> conn
    end
  end
end
