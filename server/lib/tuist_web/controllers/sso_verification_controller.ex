defmodule TuistWeb.SSOVerificationController do
  use TuistWeb, :controller

  alias Tuist.Accounts

  def verify(conn, %{"organization_id" => organization_id, "return_to" => return_to}) do
    case Accounts.get_organization_by_id(organization_id) do
      {:ok, organization} when not is_nil(organization.sso_provider) ->
        conn
        |> put_session(:oauth_return_to, return_to)
        |> redirect_to_sso_provider(organization)

      _ ->
        conn
        |> redirect(to: return_to)
        |> halt()
    end
  end

  def verify(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  defp redirect_to_sso_provider(conn, %{sso_provider: :google} = _organization) do
    conn
    |> redirect(to: ~p"/users/auth/google")
    |> halt()
  end

  defp redirect_to_sso_provider(conn, %{id: organization_id, sso_provider: :okta}) do
    conn
    |> redirect(to: ~p"/users/auth/okta?organization_id=#{organization_id}")
    |> halt()
  end
end
