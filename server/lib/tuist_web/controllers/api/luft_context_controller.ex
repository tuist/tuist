defmodule TuistWeb.API.LuftContextController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication

  def show(conn, %{"account_handle" => handle}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with %User{} = authenticated_user <- Authentication.app_user(conn) || {:error, :app_required},
         # Authentication may carry a snapshot. Membership and deactivation must
         # reflect the authority's current state, not that snapshot's roles.
         %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(authenticated_user.id),
         true <- FeatureFlags.luft_enabled?(user),
         %Account{} = account <- Accounts.get_account_by_handle(handle),
         {:ok, people} <- people(user, account) do
      json(conn, %{
        user_id: user.id,
        account_id: account.id,
        organization_id: account.organization_id,
        can_create_threads: Authorization.authorize(:account_update, user, account) == :ok,
        people: Enum.map(people, &%{id: &1.id, handle: &1.account.name, active: &1.active})
      })
    else
      {:error, :app_required} ->
        conn |> put_status(:forbidden) |> json(%{message: "Only a signed-in user can access Luft."})

      _ ->
        conn |> put_status(:not_found) |> json(%{message: "Not found."})
    end
  end

  defp people(user, %Account{organization_id: nil, user_id: owner_id}) do
    if user.id == owner_id, do: {:ok, [user]}, else: {:error, :not_found}
  end

  defp people(user, %Account{organization_id: organization_id} = account) do
    with true <- FeatureFlags.organization_luft_enabled?(account),
         {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
         true <- Accounts.belongs_to_organization?(user, organization) do
      people =
        organization
        |> Accounts.get_organization_members()
        |> Enum.filter(&(&1.active and is_nil(&1.disabled_at)))
        |> Enum.uniq_by(& &1.id)

      {:ok, people}
    else
      _ -> {:error, :not_found}
    end
  end
end
