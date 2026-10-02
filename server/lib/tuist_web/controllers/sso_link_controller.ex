defmodule TuistWeb.SSOLinkController do
  @moduledoc """
  Confirms linking an Okta or custom OAuth 2.0 identity to the signed-in
  account.

  The SSO callback stores the identity it could not link automatically in the
  session and sends the signed-in user here. Nothing is linked until they
  confirm, and the stored identity is only honored for the same user, for a
  short time, while they are a member, and while the organization still uses
  the same provider.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  @max_age_seconds 600
  @sso_providers %{"okta" => :okta, "oauth2" => :oauth2}

  def show(conn, _params) do
    case pending_link(conn) do
      {:ok, link} ->
        render_page(conn, :show,
          email: conn.assigns.current_user.email,
          identity_email: link.email,
          organization_name: link.organization_name
        )

      :error ->
        render_expired(conn)
    end
  end

  def create(conn, _params) do
    user = conn.assigns.current_user

    with {:ok, link} <- pending_link(conn),
         {:ok, _identity} <-
           Accounts.link_oauth_identity_to_user(user, %{
             provider: link.provider,
             id_in_provider: link.uid,
             provider_organization_id: link.provider_organization_id
           }) do
      conn
      |> delete_session(:pending_sso_link)
      |> put_session(:user_return_to, return_to(link, user))
      |> Authentication.log_in_user(user, %{auth_method: link.provider})
    else
      :error ->
        render_expired(conn)

      {:error, _changeset} ->
        conn
        |> delete_session(:pending_sso_link)
        |> put_status(:conflict)
        |> render_page(:status,
          title: dgettext("dashboard_auth", "Already linked"),
          subtitle:
            dgettext(
              "dashboard_auth",
              "This identity provider account is already linked to another Tuist account."
            )
        )
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:pending_sso_link)
    |> redirect(to: Authentication.signed_in_path(conn.assigns.current_user))
  end

  defp pending_link(conn) do
    user = conn.assigns.current_user

    with %{
           "user_id" => user_id,
           "organization_id" => organization_id,
           "provider" => provider,
           "uid" => uid,
           "provider_organization_id" => provider_organization_id,
           "email" => email,
           "issued_at" => issued_at
         } = link <- get_session(conn, :pending_sso_link),
         true <- user_id == user.id,
         true <- System.system_time(:second) - issued_at <= @max_age_seconds,
         {:ok, provider} <- Map.fetch(@sso_providers, provider),
         {:ok, organization} <- Accounts.get_organization_by_id(organization_id),
         true <-
           organization.sso_provider == provider and
             organization.sso_organization_id == provider_organization_id,
         true <- Accounts.belongs_to_organization?(user, organization) do
      {:ok,
       %{
         provider: provider,
         uid: uid,
         provider_organization_id: provider_organization_id,
         email: email,
         organization_name: Accounts.get_account_from_organization(organization).name,
         return_to: link["return_to"]
       }}
    else
      _ -> :error
    end
  end

  defp return_to(link, user), do: local_path(link.return_to) || Authentication.signed_in_path(user)

  defp local_path("/" <> _ = path) do
    if String.starts_with?(path, "//"), do: nil, else: path
  end

  defp local_path(_path), do: nil

  defp render_expired(conn) do
    conn
    |> delete_session(:pending_sso_link)
    |> put_status(:gone)
    |> render_page(:status,
      title: dgettext("dashboard_auth", "Link expired"),
      subtitle: dgettext("dashboard_auth", "Sign in with single sign-on again to link your account.")
    )
  end

  defp render_page(conn, template, assigns) do
    conn
    |> put_view(TuistWeb.SSOLinkHTML)
    |> render(template, Keyword.put(assigns, :head_title, dgettext("dashboard_auth", "Link single sign-on · Tuist")))
  end
end
