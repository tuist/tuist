defmodule TuistWeb.UserMFAController do
  use TuistWeb, :controller

  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserPasskey
  alias Tuist.Accounts.UserToken
  alias TuistWeb.Authentication
  alias TuistWeb.Endpoint
  alias TuistWeb.UserPasskeyController

  plug :private_response

  def challenge(conn, _params) do
    render_challenge(conn, error: nil)
  end

  def passkey_options(conn, _params) do
    pending = get_session(conn, :pending_mfa)

    with true <- UserPasskeyController.enabled?(),
         %UserToken{} = challenge <- UserMFA.get_challenge(pending) do
      {passkey_challenge, options} = UserPasskey.authentication_options(challenge.user)
      token = UserPasskeyController.encrypt_ceremony(conn, mfa_purpose(pending), passkey_challenge)
      json(conn, %{publicKey: options, token: token})
    else
      _ -> conn |> put_status(:not_found) |> json(%{})
    end
  end

  def verify(conn, params) do
    proof = challenge_proof(conn, params)

    case UserMFA.complete_challenge(get_session(conn, :pending_mfa), proof) do
      {:ok, session} ->
        auth =
          session
          |> UserMFA.auth_params()
          |> Map.put("remember_me", if(get_session(conn, :pending_mfa_remember), do: "true", else: "false"))

        # Signing in renews and clears the session, pending challenge included.
        Authentication.log_in_user_session(conn, session, auth)

      {:error, :challenge_expired} ->
        conn |> delete_session(:pending_mfa) |> redirect(to: ~p"/users/log_in")

      {:error, _} ->
        error = if params["credential_id"], do: passkey_failed(), else: invalid_code()

        conn
        |> put_status(:unauthorized)
        |> render_challenge(error: error)
    end
  end

  # A passkey assertion answers the challenge instead of a code. Its ceremony
  # token is bound to this browser's pending challenge.
  defp challenge_proof(conn, %{"credential_id" => _} = params) do
    purpose = mfa_purpose(get_session(conn, :pending_mfa))

    challenge =
      UserPasskeyController.enabled?() && UserPasskeyController.decrypt_ceremony(conn, purpose, params["challenge_token"])

    case challenge do
      %Wax.Challenge{} = challenge -> UserPasskey.challenge_verifier(challenge, params)
      # Not a code guess: keep it out of the authenticator app's attempt budget.
      _ -> fn _user -> {:error, :invalid_passkey} end
    end
  end

  defp challenge_proof(_conn, params), do: params["mfa_code"]

  defp mfa_purpose(pending) when is_binary(pending), do: {:mfa, :crypto.hash(:sha256, pending)}
  defp mfa_purpose(_pending), do: {:mfa, nil}

  def show(conn, _params) do
    redirect(conn, to: ~p"/#{conn.assigns.current_user.account.name}/settings/two-factor-authentication")
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

  def regenerate(conn, params) do
    case UserMFA.regenerate_recovery_codes(
           conn.assigns.current_user,
           conn.assigns.current_user_session,
           params["mfa_code"]
         ) do
      {:ok, result} ->
        conn |> rotate_session(result) |> render_page(:recovery, codes: result.recovery_codes)

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render_page(:settings,
          enabled: true,
          secret: nil,
          proof_action: :regenerate,
          error: reauthenticate() <> " " <> invalid_code()
        )
    end
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

  @doc false
  def rotate_session(conn, result) do
    Enum.each(result.revoked_sessions, &Endpoint.broadcast(&1, "disconnect", %{}))

    # Factor changes revoke every old session, then rotate this browser into a
    # verified session created in the same transaction as the factor change.
    conn
    |> configure_session(renew: true)
    |> put_session(:user_token, result.session.token)
    |> put_session(:live_socket_id, UserToken.live_socket_id(result.session))
    |> Authentication.delete_remember_me_cookie()
  end

  defp private_response(conn, _opts) do
    conn |> put_resp_header("cache-control", "private, no-store") |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp render_challenge(conn, assigns) do
    case UserMFA.get_challenge(get_session(conn, :pending_mfa)) do
      nil ->
        redirect(conn, to: ~p"/users/log_in")

      challenge ->
        passkeys? = UserPasskeyController.enabled?() and UserPasskey.list(challenge.user) != []
        render_page(conn, :challenge, Keyword.merge(assigns, email: challenge.user.email, passkeys?: passkeys?))
    end
  end

  defp render_page(conn, template, assigns) do
    conn
    |> put_view(TuistWeb.UserMFAHTML)
    |> render(
      template,
      assigns
      |> Keyword.put_new(:proof_action, :disable)
      |> Keyword.put(:head_title, dgettext("dashboard_auth", "Two-factor authentication · Tuist"))
    )
  end

  defp reauthenticate,
    do: dgettext("dashboard_auth", "Sign out and sign in again before changing two-factor authentication.")

  defp passkey_failed, do: dgettext("dashboard_auth", "The passkey could not be verified. Try again.")

  defp invalid_code,
    do:
      dgettext(
        "dashboard_auth",
        "The code is invalid, already used, or too many attempts were made. Try a new code later."
      )
end
