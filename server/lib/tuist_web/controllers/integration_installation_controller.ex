defmodule TuistWeb.IntegrationInstallationController do
  @moduledoc "Organization selection for verified, provider-initiated installations."
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.GitHub.Installations
  alias Tuist.Origin
  alias Tuist.Origin.Signatures
  alias Tuist.VCS
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.BadRequestError

  def select(conn, provider, proof) when provider in [:github, :origin] do
    user = Authentication.current_user(conn)

    conn
    |> put_session(:integration_installation, %{
      provider: provider,
      proof: proof,
      user_id: user.id,
      issued_at: System.system_time(:second)
    })
    |> redirect(to: ~p"/integrations/installation")
  end

  def show(conn, _params) do
    pending = pending!(conn)
    user = Authentication.current_user(conn)
    {:ok, account} = Accounts.get_account_by_id(user.account.id)

    accounts =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account)
      |> Enum.concat([account])
      |> Enum.filter(&(Authorization.authorize(:account_update, user, &1) == :ok))
      |> Enum.sort_by(&String.downcase(&1.name))

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_view(html: TuistWeb.IntegrationInstallationHTML)
    |> render(:show,
      head_title: dgettext("dashboard_auth", "Choose an organization · Tuist"),
      provider: provider_name(pending.provider),
      accounts: accounts
    )
  end

  def create(conn, %{"account_id" => account_id}) when is_binary(account_id) do
    pending = pending!(conn)
    user = Authentication.current_user(conn)

    with {account_id, ""} <- Integer.parse(account_id),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, user, account),
         {:ok, _installation} <- attach(pending, account) do
      conn
      |> delete_session(:integration_installation)
      |> redirect(to: ~p"/#{account.name}/settings/integrations")
    else
      {:error, :github_host_conflict} ->
        raise BadRequestError,
              dgettext("dashboard", "This account already has a GitHub App registered for a different GitHub host.")

      _ ->
        invalid_request!()
    end
  end

  def create(_conn, _params), do: invalid_request!()

  def delete(conn, _params) do
    conn |> delete_session(:integration_installation) |> redirect(to: ~p"/dashboard")
  end

  defp pending!(conn) do
    user = Authentication.current_user(conn)

    case get_session(conn, :integration_installation) do
      %{user_id: user_id, issued_at: issued_at, provider: provider} = pending
      when user_id == user.id and provider in [:github, :origin] and is_integer(issued_at) ->
        if (System.system_time(:second) - issued_at) in -60..600, do: pending, else: invalid_request!()

      _ ->
        invalid_request!()
    end
  end

  defp attach(%{provider: :origin, proof: receipt}, account) do
    with {:ok, claims} <- Signatures.verify_receipt(receipt, nil) do
      Origin.attach_installation(account, claims)
    end
  end

  defp attach(%{provider: :github, proof: installation_id}, account) do
    Installations.attach(account, VCS.default_client_url(), installation_id)
  end

  defp provider_name(:github), do: "GitHub"
  defp provider_name(:origin), do: "Cursor Origin"

  defp invalid_request! do
    raise BadRequestError, dgettext("dashboard", "Invalid installation request. Please try again.")
  end
end
