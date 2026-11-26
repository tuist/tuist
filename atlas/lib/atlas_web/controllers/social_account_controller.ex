defmodule AtlasWeb.SocialAccountController do
  @moduledoc """
  Connects an X account or a LinkedIn Page to Atlas for post tracking. The
  grant is stored on the account (`Atlas.GTM.SocialAccounts`), not on the
  person who signs in. Callbacks are `/connections/<platform>/callback`, the
  URLs registered in the X and LinkedIn developer apps.
  """

  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Connections.Provider
  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialAccounts

  @salt "social-account-connection"
  @accounts_path "/commercial/gtm/social/performance"

  plug :no_store

  def authorize(conn, %{"kind" => kind} = params) do
    user = conn.assigns.current_user
    platform = params["platform"] || "x"
    verifier = random_token()
    nonce = random_token()
    state = Phoenix.Token.sign(conn, @salt, %{user_id: user.id, platform: platform, kind: kind, nonce: nonce})

    with true <- SocialAccounts.can_manage?(user),
         true <- platform in SocialAccount.platforms(),
         true <- kind in SocialAccount.kinds(),
         {:ok, location} <- Provider.authorization_url(platform, callback_url(platform), state, verifier) do
      conn
      |> put_session(:social_account_connection, %{
        user_id: user.id,
        platform: platform,
        kind: kind,
        nonce: nonce,
        verifier: verifier
      })
      |> redirect(external: location)
    else
      _ -> fail(conn)
    end
  end

  def callback(conn, params) do
    platform = conn.assigns.platform
    pending = get_session(conn, :social_account_connection)
    conn = delete_session(conn, :social_account_connection)
    user = conn.assigns.current_user

    with {:ok, kind, verifier} <- verify_state(conn, params["state"], pending, user.id, platform),
         nil <- params["error"],
         code when is_binary(code) and code != "" <- params["code"],
         {:ok, account} <-
           Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
             SocialAccounts.connect(user, platform, kind, code, callback_url(platform), verifier)
           end) do
      conn
      |> put_flash(:info, gettext("Connected %{handle}.", handle: account.handle))
      |> redirect(to: @accounts_path)
    else
      _ -> fail(conn)
    end
  end

  # The signed state must match the pending session, which a callback consumes once.
  defp verify_state(
         conn,
         state,
         %{user_id: user_id, platform: platform, kind: kind, nonce: nonce, verifier: verifier},
         user_id,
         platform
       )
       when is_binary(state) do
    case Phoenix.Token.verify(conn, @salt, state, max_age: 600) do
      {:ok, %{user_id: ^user_id, platform: ^platform, kind: ^kind, nonce: ^nonce}} -> {:ok, kind, verifier}
      _ -> {:error, :invalid_state}
    end
  end

  defp verify_state(_conn, _state, _pending, _user_id, _platform), do: {:error, :invalid_state}

  defp callback_url(platform), do: AtlasWeb.Endpoint.url() <> "/connections/#{platform}/callback"

  defp random_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")

  defp fail(conn) do
    conn
    |> put_flash(:error, gettext("Could not connect the account. Please try again."))
    |> redirect(to: @accounts_path)
  end
end
