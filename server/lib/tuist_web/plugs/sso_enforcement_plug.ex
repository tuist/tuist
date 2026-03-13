defmodule TuistWeb.Plugs.SSOEnforcementPlug do
  @moduledoc false
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Accounts

  def init(opts), do: opts

  def call(%{params: %{"account_handle" => account_handle}} = conn, _opts) do
    with account when not is_nil(account) <- Accounts.get_account_by_handle(account_handle),
         organization_id when not is_nil(organization_id) <- account.organization_id,
         {:ok, organization} <- Accounts.get_organization_by_id(organization_id),
         true <- organization.sso_enforced and not is_nil(organization.sso_provider),
         auth_provider = get_session(conn, :auth_provider),
         false <- auth_provider == organization.sso_provider do
      return_to = ~p"/#{account_handle}/projects"

      conn
      |> put_session(:oauth_return_to, return_to)
      |> redirect_to_sso_provider(organization)
      |> halt()
    else
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp redirect_to_sso_provider(conn, %{sso_provider: :google}) do
    redirect(conn, to: ~p"/users/auth/google")
  end

  defp redirect_to_sso_provider(conn, %{id: organization_id, sso_provider: :okta}) do
    redirect(conn, to: ~p"/users/auth/okta?organization_id=#{organization_id}")
  end
end
