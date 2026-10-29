defmodule TuistWeb.UserMFAController do
  use TuistWeb, :controller

  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserToken
  alias TuistWeb.Authentication
  alias TuistWeb.Endpoint

  plug :private_response

  def challenge(conn, _params) do
    render_challenge(conn, error: nil, recovery: false)
  end

  def verify(conn, params) do
    case UserMFA.complete_challenge(get_session(conn, :pending_mfa), params["mfa_code"]) do
      {:ok, session} ->
        auth =
          session
          |> UserMFA.auth_params()
          |> Map.put("remember_me", if(get_session(conn, :pending_mfa_remember), do: "true", else: "false"))

        conn
        |> delete_session(:pending_mfa)
        |> Authentication.log_in_user_session(session, auth)

      {:error, :challenge_expired} ->
        conn |> delete_session(:pending_mfa) |> redirect(to: ~p"/users/log_in")

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render_challenge(error: invalid_code(), recovery: params["recovery"] == "true")
    end
  end

  def show(conn, _params) do
    render_page(conn, :settings, enabled: UserMFA.enabled?(conn.assigns.current_user), error: nil, secret: nil)
  end

  def enroll(conn, _params) do
    case UserMFA.begin_enrollment(conn.assigns.current_user, conn.assigns.current_user_session) do
      {:ok, factor} ->
        render_page(conn, :settings, enabled: false, error: nil, secret: factor.secret)

      {:error, _} ->
        conn |> put_status(:forbidden) |> render_page(:settings, enabled: false, secret: nil, error: reauthenticate())
    end
  end

  def confirm(conn, params) do
    case UserMFA.confirm_enrollment(conn.assigns.current_user, conn.assigns.current_user_session, params["mfa_code"]) do
      {:ok, result} ->
        conn
        |> rotate_session(result)
        |> render_page(:recovery, codes: result.recovery_codes)

      {:error, _} ->
        secret =
          case UserMFA.get_pending_enrollment(conn.assigns.current_user, conn.assigns.current_user_session) do
            nil -> nil
            factor -> factor.secret
          end

        conn
        |> put_status(:unauthorized)
        |> render_page(:settings, enabled: false, secret: secret, error: invalid_code())
    end
  end

  def cancel(conn, _params) do
    :ok = UserMFA.cancel_enrollment(conn.assigns.current_user, conn.assigns.current_user_session)
    redirect(conn, to: ~p"/users/settings/mfa")
  end

  def disable(conn, params) do
    case UserMFA.disable(conn.assigns.current_user, conn.assigns.current_user_session, params["mfa_code"]) do
      {:ok, result} ->
        conn |> rotate_session(result) |> redirect(to: ~p"/users/settings/mfa")

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render_page(:settings, enabled: true, secret: nil, error: reauthenticate() <> " " <> invalid_code())
    end
  end

  defp rotate_session(conn, result) do
    Enum.each(result.revoked_sessions, &Endpoint.broadcast(&1, "disconnect", %{}))

    # Factor changes revoke every old session, then rotate this browser into a
    # verified session created in the same transaction as the factor change.
    conn
    |> configure_session(renew: true)
    |> put_session(:user_token, result.session.token)
    |> put_session(:live_socket_id, UserToken.live_socket_id(result.session))
    |> delete_resp_cookie("_tuist_web_user_remember_me")
  end

  defp private_response(conn, _opts) do
    conn |> put_resp_header("cache-control", "private, no-store") |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp render_challenge(conn, assigns) do
    case UserMFA.get_challenge(get_session(conn, :pending_mfa)) do
      nil -> redirect(conn, to: ~p"/users/log_in")
      challenge -> render_page(conn, :challenge, Keyword.put(assigns, :email, challenge.user.email))
    end
  end

  defp render_page(conn, template, assigns) do
    conn
    |> put_layout(false)
    |> put_view(TuistWeb.UserMFAHTML)
    |> render(
      template,
      Keyword.put(assigns, :head_title, dgettext("dashboard_auth", "Two-factor authentication · Tuist"))
    )
  end

  defp reauthenticate,
    do: dgettext("dashboard_auth", "Sign out and sign in again before changing two-factor authentication.")

  defp invalid_code,
    do:
      dgettext(
        "dashboard_auth",
        "The code is invalid, already used, or too many attempts were made. Try a new code later."
      )
end
