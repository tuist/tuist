defmodule TuistWeb.UserResetPasswordController do
  @moduledoc """
  POST fallback when LiveView is unavailable or a password manager submits the form.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.Endpoint

  def update(conn, %{"token" => token} = params) do
    if Environment.email_auth_enabled?() do
      case Accounts.reset_user_password(token, Map.get(params, "user", %{})) do
        {:ok, %{revoked_session_live_socket_ids: ids}} ->
          Enum.each(ids, &Endpoint.broadcast(&1, "disconnect", %{}))

          conn
          |> put_flash(:info, dgettext("dashboard_auth", "Password reset successfully."))
          |> redirect(to: ~p"/users/log_in")

        {:error, :invalid_token} ->
          conn
          |> put_flash(:error, dgettext("dashboard_auth", "Reset password link is invalid or it has expired."))
          |> redirect(to: ~p"/users/log_in")

        {:error, _changeset} ->
          conn
          |> put_flash(
            :error,
            dgettext("dashboard_auth", "Check that your passwords match and meet the password requirements.")
          )
          |> redirect(to: ~p"/users/reset_password/#{token}")
      end
    else
      redirect(conn, to: ~p"/users/log_in")
    end
  end
end
