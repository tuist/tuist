defmodule TuistWeb.InvitationController do
  @moduledoc """
  Handles acceptance and decline of organization invitations via email links.

  Accept is exposed as a POST so it can both (a) mutate state and (b) log the
  invitee in on first click without requiring them to authenticate with the
  org's SSO provider first — which can deadlock an existing Tuist user whose
  account predates the org's SSO configuration.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def accept(conn, %{"token" => token}) do
    session_user = Authentication.current_user(conn)

    with {:ok, invitation} <- Accounts.get_invitation_by_token(token),
         {:ok, organization} <- Accounts.get_organization_by_id(invitation.organization_id),
         {:ok, invitee} <- resolve_invitee(session_user, invitation) do
      Accounts.accept_invitation(%{
        invitation: invitation,
        invitee: invitee,
        organization: organization
      })

      if session_user && session_user.id == invitee.id do
        conn
        |> put_flash(
          :info,
          dgettext("dashboard_account", "You are now a part of the organization.")
        )
        |> redirect(to: Authentication.signed_in_path(invitee))
      else
        Authentication.log_in_user(conn, invitee)
      end
    else
      {:error, :not_found} ->
        conn
        |> put_flash(
          :error,
          dgettext(
            "dashboard_account",
            "We could not find the invitation you are trying to accept. Please ask the inviter to send a new invitation."
          )
        )
        |> redirect(to: ~p"/users/log_in")

      {:error, :mismatched_session_user, invitee_email} ->
        conn
        |> put_flash(
          :error,
          dgettext(
            "dashboard_account",
            "This invitation is addressed to %{email}. Log out and retry with that account.",
            email: invitee_email
          )
        )
        |> redirect(to: ~p"/users/log_in")

      {:error, :user_not_found, invitee_email} ->
        conn
        |> put_flash(
          :info,
          dgettext(
            "dashboard_account",
            "Create an account with %{email} to accept the invitation.",
            email: invitee_email
          )
        )
        |> redirect(to: ~p"/users/register")
    end
  end

  def decline(conn, %{"token" => token}) do
    case Accounts.get_invitation_by_token(token) do
      {:ok, invitation} ->
        Accounts.delete_invitation(%{invitation: invitation})

        conn
        |> put_flash(
          :info,
          dgettext("dashboard_account", "Invitation declined.")
        )
        |> redirect(to: ~p"/users/log_in")

      {:error, :not_found} ->
        conn
        |> put_flash(
          :error,
          dgettext("dashboard_account", "Invitation not found.")
        )
        |> redirect(to: ~p"/users/log_in")
    end
  end

  defp resolve_invitee(nil, invitation) do
    case Accounts.get_user_by_email(invitation.invitee_email) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> {:error, :user_not_found, invitation.invitee_email}
    end
  end

  defp resolve_invitee(%{email: email} = session_user, %{invitee_email: email}), do: {:ok, session_user}

  defp resolve_invitee(_session_user, invitation), do: {:error, :mismatched_session_user, invitation.invitee_email}
end
