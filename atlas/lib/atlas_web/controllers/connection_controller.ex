defmodule AtlasWeb.ConnectionController do
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Connections.Provider
  alias AtlasWeb.NativeLinks.Config
  alias AtlasWeb.Plugs.NativeOAuthClient

  @salt "personal-account-connection"
  @native_salt "native-account-connection"

  plug NativeOAuthClient when action in [:prepare]
  plug :no_store

  def index(conn, _params), do: json(conn, %{connections: Connections.list(conn.assigns.current_user)})

  def delete(conn, %{"provider" => provider}) do
    result =
      Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
        Connections.disconnect(conn.assigns.current_user, provider)
      end)

    case result do
      {:ok, :ok} -> json(conn, %{disconnected: true})
      {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "connection_disconnect_failed"})
    end
  end

  def prepare(conn, %{"provider" => provider}) do
    with %{"state" => state} when map_size(conn.body_params) == 1 <- conn.body_params,
         true <- native_state?(state),
         {:ok, _} <- Provider.config(provider),
         origin when is_binary(origin) <- Config.origin() do
      ticket =
        Phoenix.Token.sign(conn, @native_salt, %{
          user_id: conn.assigns.current_user.id,
          provider: provider,
          client_id: conn.assigns.oauth_client_id,
          state: state
        })

      json(conn, %{
        authorization_url: origin <> "/connections/#{provider}/authorize?" <> URI.encode_query(%{native: ticket})
      })
    else
      _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_connection_authorization"})
    end
  end

  def authorize(conn, %{"provider" => provider} = params) do
    # A ticket binds the native caller to an already authenticated browser user.
    # It is never a browser sign-in credential or a provider OAuth state.
    case native_context(conn, params, provider) do
      {:ok, native} -> begin_authorization(conn, provider, native)
      _ -> fail(delete_session(conn, :account_connection), gettext("Could not connect your account. Please try again."))
    end
  end

  defp begin_authorization(conn, provider, native) do
    verifier = random_token()
    nonce = random_token()
    user = conn.assigns.current_user
    state = Phoenix.Token.sign(conn, @salt, %{user_id: user.id, provider: provider, nonce: nonce})

    with {:ok, location} <- Provider.authorization_url(provider, callback_url(provider), state, verifier),
         {:ok, _} <- Connections.begin_authorization(user, provider, nonce) do
      conn
      |> put_session(:account_connection, %{
        user_id: user.id,
        provider: provider,
        nonce: nonce,
        verifier: verifier,
        native: native
      })
      |> redirect(external: location)
    else
      _ ->
        finish(delete_session(conn, :account_connection), native, provider, "error")
    end
  end

  defp native_context(conn, %{"native" => ticket}, provider) when is_binary(ticket) do
    user_id = conn.assigns.current_user.id

    with {:ok, %{user_id: ^user_id, provider: ^provider, client_id: client_id, state: state} = native} <-
           Phoenix.Token.verify(conn, @native_salt, ticket, max_age: 600),
         {:ok, _} <- Ecto.UUID.cast(client_id),
         true <- native_state?(state) do
      {:ok, native}
    else
      _ -> {:error, :invalid_ticket}
    end
  end

  defp native_context(_conn, params, _provider) do
    if Map.has_key?(params, "native"), do: {:error, :invalid_ticket}, else: {:ok, nil}
  end

  def callback(conn, %{"provider" => provider} = params) do
    pending = get_session(conn, :account_connection)
    conn = delete_session(conn, :account_connection)
    user = conn.assigns.current_user
    native = pending_native(pending, user.id, provider)

    with {:ok, verifier} <- verify_state(conn, params["state"], pending, user.id, provider),
         nil <- params["error"],
         code when is_binary(code) and code != "" <- params["code"],
         {:ok, _connection} <-
           Audit.with_context(%{actor: user, interface: if(native, do: "api", else: "dashboard")}, fn ->
             Connections.connect(user, provider, code, callback_url(provider), verifier)
           end) do
      finish(conn, native, provider, "connected")
    else
      _ -> finish(conn, native, provider, "error")
    end
  end

  defp verify_state(conn, state, pending, user_id, provider) when is_binary(state) and is_map(pending) do
    with {:ok, %{user_id: ^user_id, provider: ^provider, nonce: nonce}} <-
           Phoenix.Token.verify(conn, @salt, state, max_age: 600),
         %{user_id: ^user_id, provider: ^provider, nonce: ^nonce, verifier: verifier} <- pending,
         :ok <- Connections.consume_authorization(user_id, provider, nonce) do
      {:ok, verifier}
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp verify_state(_conn, _state, _pending, _user_id, _provider), do: {:error, :invalid_state}

  defp pending_native(%{user_id: user_id, provider: provider, native: native}, user_id, provider), do: native
  defp pending_native(_pending, _user_id, _provider), do: nil

  defp finish(conn, %{state: state}, provider, status) do
    query = URI.encode_query(%{state: state, provider: provider, status: status})
    redirect(conn, external: "dev.tuist.atlas://connections-callback?" <> query)
  end

  defp finish(conn, nil, _provider, "connected") do
    conn |> put_flash(:info, gettext("Account connected.")) |> redirect(to: ~p"/settings/connections")
  end

  defp finish(conn, nil, _provider, "error"),
    do: fail(conn, gettext("Could not connect your account. Please try again."))

  defp callback_url(provider), do: AtlasWeb.Endpoint.url() <> "/connections/#{provider}/callback"

  defp native_state?(state) when is_binary(state), do: Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, state)
  defp native_state?(_state), do: false

  defp random_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")

  defp fail(conn, message) do
    conn |> put_flash(:error, message) |> redirect(to: ~p"/settings/connections")
  end
end
