defmodule AtlasWeb.SocialAccountController do
  @moduledoc """
  Connects an X account to Atlas for post tracking. The grant is stored on the
  account (`Atlas.GTM.SocialAccounts`), not on the person who signs in to X.
  The callback keeps `/connections/x/callback`, the URL registered in the X app.
  """

  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Connections.Provider
  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialAccounts

  @salt "social-account-connection"
  @accounts_path "/commercial/gtm/social/performance"

  plug :no_store

  def authorize(conn, %{"kind" => kind}) do
    user = conn.assigns.current_user
    verifier = random_token()
    nonce = random_token()
    state = Phoenix.Token.sign(conn, @salt, %{user_id: user.id, kind: kind, nonce: nonce})

    with true <- SocialAccounts.can_manage?(user),
         true <- kind in SocialAccount.kinds(),
         {:ok, location} <- Provider.authorization_url("x", callback_url(), state, verifier) do
      conn
      |> put_session(:social_account_connection, %{user_id: user.id, kind: kind, nonce: nonce, verifier: verifier})
      |> redirect(external: location)
    else
      _ -> fail(conn)
    end
  end

  def callback(conn, params) do
    pending = get_session(conn, :social_account_connection)
    conn = delete_session(conn, :social_account_connection)
    user = conn.assigns.current_user

    with {:ok, kind, verifier} <- verify_state(conn, params["state"], pending, user.id),
         nil <- params["error"],
         code when is_binary(code) and code != "" <- params["code"],
         {:ok, account} <-
           Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
             SocialAccounts.connect(user, kind, code, callback_url(), verifier)
           end) do
      conn
      |> put_flash(:info, gettext("Connected %{handle}.", handle: account.handle))
      |> redirect(to: @accounts_path)
    else
      _ -> fail(conn)
    end
  end

  # The signed state must match the pending session, which a callback consumes once.
  defp verify_state(conn, state, %{user_id: user_id, kind: kind, nonce: nonce, verifier: verifier}, user_id)
       when is_binary(state) do
    case Phoenix.Token.verify(conn, @salt, state, max_age: 600) do
      {:ok, %{user_id: ^user_id, kind: ^kind, nonce: ^nonce}} -> {:ok, kind, verifier}
      _ -> {:error, :invalid_state}
    end
  end

  defp verify_state(_conn, _state, _pending, _user_id), do: {:error, :invalid_state}

  defp callback_url, do: AtlasWeb.Endpoint.url() <> "/connections/x/callback"

  defp random_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")

  defp fail(conn) do
    conn
    |> put_flash(:error, gettext("Could not connect the X account. Please try again."))
    |> redirect(to: @accounts_path)
  end
end
