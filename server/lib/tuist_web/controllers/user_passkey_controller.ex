defmodule TuistWeb.UserPasskeyController do
  @moduledoc """
  Passkey registration and removal from the passkey settings page, and
  passwordless sign-in. Option endpoints answer JSON for
  `navigator.credentials`; the browser then posts the result as a form so
  sign-in keeps the same redirects and session handling as other methods.

  Each options response carries its WebAuthn challenge in an encrypted,
  five-minute ceremony token that the browser posts back with the result.
  Keeping it out of the cookie session matters: the sign-in page runs several
  requests at once (autofill, the passkey button, Google One Tap), and with a
  cookie session the last response to arrive would overwrite the challenge.
  Each passkey accepts only challenges newer than the last one it answered,
  so a token cannot be replayed.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts.UserPasskey
  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit
  alias TuistWeb.UserMFAController

  @token_salt "passkey ceremony"

  plug :private_response
  plug :require_passkeys_enabled

  def show(conn, _params) do
    redirect(conn, to: ~p"/#{conn.assigns.current_user.account.name}/settings/passkeys")
  end

  def new(conn, _params) do
    conn
    |> put_view(TuistWeb.UserPasskeyHTML)
    |> render(:settings,
      head_title: dgettext("dashboard_auth", "Add a passkey · Tuist")
    )
  end

  def registration_options(conn, _params) do
    %{current_user: user, current_user_session: session} = conn.assigns

    case UserPasskey.registration_options(user, session) do
      {:ok, {state, options}} ->
        json(conn, %{publicKey: options, token: encrypt_ceremony(conn, {:registration, user.id}, state)})

      {:error, reason} ->
        conn |> put_status(:forbidden) |> json(%{error: error_message(reason)})
    end
  end

  def create(conn, params) do
    %{current_user: user, current_user_session: session} = conn.assigns

    result =
      case decrypt_ceremony(conn, {:registration, user.id}, params["challenge_token"]) do
        nil -> {:error, :invalid_passkey}
        state -> UserPasskey.register(user, session, state, params)
      end

    case result do
      {:ok, _passkey} ->
        conn
        |> put_flash(:info, dgettext("dashboard_auth", "Passkey added."))
        |> redirect(to: ~p"/users/settings/passkeys")

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> redirect(to: ~p"/users/settings/passkeys")
    end
  end

  def rename(conn, %{"id" => id} = params) do
    %{current_user: user, current_user_session: session} = conn.assigns

    case UserPasskey.rename(user, session, id, params["name"]) do
      {:ok, _passkey} ->
        conn
        |> put_flash(:info, dgettext("dashboard_auth", "Passkey renamed."))
        |> redirect(to: ~p"/users/settings/passkeys")

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> redirect(to: ~p"/users/settings/passkeys")
    end
  end

  def confirm_delete(conn, %{"id" => id}) do
    passkeys = UserPasskey.list(conn.assigns.current_user)

    case Enum.find(passkeys, &(to_string(&1.id) == id)) do
      nil ->
        send_resp(conn, :not_found, "")

      passkey ->
        conn
        |> put_view(TuistWeb.UserPasskeyHTML)
        |> render(:confirm_delete,
          passkey: passkey,
          last_passkey?: length(passkeys) == 1,
          head_title: dgettext("dashboard_auth", "Remove passkey · Tuist")
        )
    end
  end

  def delete(conn, %{"id" => id, "confirm" => "true"}) do
    %{current_user: user, current_user_session: session} = conn.assigns

    case UserPasskey.delete(user, session, id) do
      {:ok, result} ->
        conn
        |> UserMFAController.rotate_session(result)
        |> put_flash(:info, dgettext("dashboard_auth", "Passkey removed."))
        |> redirect(to: ~p"/users/settings/passkeys")

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> redirect(to: ~p"/users/settings/passkeys")
    end
  end

  def delete(conn, %{"id" => id}) do
    redirect(conn, to: ~p"/users/settings/passkeys/#{id}/delete")
  end

  def authentication_options(conn, _params) do
    {challenge, options} = UserPasskey.authentication_options()
    json(conn, %{publicKey: options, token: encrypt_ceremony(conn, :authentication, challenge)})
  end

  def authenticate(conn, params) do
    with {:allow, _count} <- RateLimit.Auth.hit(conn),
         %Wax.Challenge{} = challenge <- decrypt_ceremony(conn, :authentication, params["challenge_token"]),
         {:ok, session} <- UserPasskey.authenticate(challenge, params) do
      # The assertion was user-verified, so the session is MFA-verified.
      conn
      |> put_flash(:info, "Welcome back!")
      |> Authentication.log_in_user_session(session, %{auth_method: :passkey})
    else
      _ ->
        conn
        |> put_flash(:passkey_error, dgettext("dashboard_auth", "The passkey could not be verified. Try again."))
        |> redirect(to: ~p"/users/log_in")
    end
  end

  @doc false
  def enabled?, do: Environment.email_auth_enabled?()

  # A passkey is a first factor, like a password. Instances that turn off
  # email and password sign-in to rely on their identity provider must not
  # gain a sign-in method that outlives the provider's account lifecycle.
  defp require_passkeys_enabled(conn, _opts) do
    if enabled?(), do: conn, else: conn |> send_resp(:not_found, "") |> halt()
  end

  @doc false
  def encrypt_ceremony(conn, purpose, state), do: Phoenix.Token.encrypt(conn, @token_salt, {purpose, state})

  # Returns the ceremony state only for the purpose it was issued for, so a
  # token from one ceremony, user or MFA challenge cannot complete another.
  @doc false
  def decrypt_ceremony(conn, purpose, token) when is_binary(token) do
    case Phoenix.Token.decrypt(conn, @token_salt, token, max_age: UserPasskey.ceremony_timeout()) do
      {:ok, {^purpose, state}} -> state
      _ -> nil
    end
  end

  def decrypt_ceremony(_conn, _purpose, _token), do: nil

  defp error_message(:reauthentication_required),
    do: dgettext("dashboard_auth", "Sign out and sign in again before changing passkeys.")

  defp error_message(:too_many_passkeys), do: dgettext("dashboard_auth", "Remove a passkey before adding another one.")

  defp error_message(:already_registered), do: dgettext("dashboard_auth", "This passkey is already registered.")

  defp error_message(_), do: dgettext("dashboard_auth", "The passkey could not be verified. Try again.")

  defp private_response(conn, _opts) do
    conn |> put_resp_header("cache-control", "private, no-store") |> put_resp_header("referrer-policy", "no-referrer")
  end
end
