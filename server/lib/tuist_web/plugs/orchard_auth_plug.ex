defmodule TuistWeb.Plugs.OrchardAuthPlug do
  @moduledoc """
  HTTP Basic auth for the embedded Orchard control plane.

  Validates `Authorization: Basic <base64(name:token)>` against the
  `orchard_service_accounts` table. On success the resolved
  `Tuist.Orchard.ServiceAccount` is assigned to `:orchard_service_account`
  on the conn so downstream controllers can enforce role checks via
  `require_role/2`.

  Init opts:

    * `:role` — required role for the request to proceed. Same enum
      Cirrus uses: `compute:read`, `compute:write`, `compute:connect`,
      `admin:read`, `admin:write`. If `nil`, the plug only authenticates
      and doesn't enforce a role; controllers can call `require_role/2`
      themselves for finer-grained checks.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Orchard

  @impl Plug
  def init(opts), do: Keyword.get(opts, :role)

  @impl Plug
  def call(conn, role) do
    with {:ok, name, token} <- decode_basic_auth(conn),
         {:ok, account} <- Orchard.authenticate_service_account(name, token) do
      conn
      |> assign(:orchard_service_account, account)
      |> maybe_check_role(role)
    else
      _ -> unauthorized(conn)
    end
  end

  @doc """
  Reject the request if the authenticated account doesn't have `role`.
  """
  def require_role(conn, role) do
    case conn.assigns[:orchard_service_account] do
      %{} = account ->
        if Orchard.has_role?(account, role) do
          conn
        else
          forbidden(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp decode_basic_auth(conn) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [name, token] <- String.split(decoded, ":", parts: 2) do
      {:ok, name, token}
    else
      _ -> :error
    end
  end

  defp maybe_check_role(conn, nil), do: conn
  defp maybe_check_role(conn, role), do: require_role(conn, role)

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="orchard"))
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"message":"unauthorized"}))
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, ~s({"message":"forbidden"}))
    |> halt()
  end
end
