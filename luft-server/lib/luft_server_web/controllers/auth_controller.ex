defmodule LuftServerWeb.AuthController do
  @moduledoc """
  Signing in with Tuist. `GET /auth/login` starts the OpenID Connect
  authorization code flow, `GET /auth/callback` completes it and sets the
  session cookie, `POST /auth/logout` ends the session.

  `/auth/login?signup=1` asks Tuist to show sign-up instead of sign-in
  (`prompt=create`), and `return_to` names the path in the Luft web app, which
  shares this origin, to land on afterwards.
  """
  use LuftServerWeb, :controller

  alias LuftServer.AuthEvents
  alias LuftServer.NativeAuth
  alias LuftServer.Sessions
  alias LuftServer.Tuist.OIDC
  alias LuftServerWeb.Auth

  def login(conn, params) do
    transaction = Map.put(OIDC.new_transaction(), "return_to", return_to(params["return_to"]))
    prompt = if params["signup"] in ["1", "true"], do: "create"

    case OIDC.authorization_url(transaction, prompt: prompt) do
      {:ok, url} ->
        conn
        |> put_session(:signin, transaction)
        |> redirect(external: url)

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "tuist_unavailable"})
    end
  end

  def callback(conn, %{"state" => state} = params) do
    transaction = get_session(conn, :signin)
    conn = delete_session(conn, :signin)

    cond do
      # The state binds the response to the browser that started the sign-in.
      not match?(%{"state" => ^state}, transaction) ->
        AuthEvents.log(:sign_in, :invalid_state, client: client(transaction))
        conn |> put_status(:bad_request) |> json(%{error: "invalid_state"})

      is_map(transaction["native"]) ->
        native_callback(configure_session(conn, drop: true), params, transaction)

      error = params["error"] ->
        AuthEvents.log(:sign_in, :denied, client: "browser")
        redirect(conn, to: with_query(transaction["return_to"], error: error))

      code = params["code"] ->
        with {:ok, signin} <- OIDC.exchange_code(code, transaction),
             {:ok, token, session} <- Sessions.create(signin) do
          AuthEvents.log(:sign_in, :success, client: "browser", session: session)

          conn
          |> configure_session(renew: true)
          |> Auth.put_session_cookie(token)
          |> redirect(to: transaction["return_to"])
        else
          {:error, _reason} ->
            AuthEvents.log(:sign_in, :failed, client: "browser")
            conn |> put_status(:bad_gateway) |> json(%{error: "sign_in_failed"})
        end

      true ->
        AuthEvents.log(:sign_in, :invalid_request, client: "browser")
        conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
    end
  end

  def callback(conn, _params) do
    AuthEvents.log(:sign_in, :invalid_request)
    conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
  end

  defp native_callback(conn, params, transaction) do
    client = client(transaction)

    if Sessions.consume_native_transaction(transaction["native_pending"]) do
      cond do
        is_binary(params["error"]) ->
          AuthEvents.log(:sign_in, :denied, client: client)

          redirect(conn,
            external: NativeAuth.callback_url(transaction["native"], error: "access_denied")
          )

        is_binary(params["code"]) ->
          with {:ok, signin} <- OIDC.exchange_code(params["code"], transaction),
               {:ok, url, session} <- NativeAuth.complete(signin, transaction["native"]) do
            AuthEvents.log(:sign_in, :success, client: client, session: session)
            redirect(conn, external: url)
          else
            _ ->
              AuthEvents.log(:sign_in, :failed, client: client)
              conn |> put_status(:bad_gateway) |> json(%{error: "sign_in_failed"})
          end

        true ->
          AuthEvents.log(:sign_in, :invalid_request, client: client)
          conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
      end
    else
      # The pending sign-in expired or was already used.
      AuthEvents.log(:sign_in, :invalid_state, client: client)
      conn |> put_status(:bad_request) |> json(%{error: "invalid_state"})
    end
  end

  def logout(conn, _params) do
    session = conn.assigns.session
    Sessions.delete(session)

    client =
      if get_req_header(conn, "authorization") == [], do: "browser", else: NativeAuth.client_id()

    AuthEvents.log(:sign_out, :success, session: session, client: client)

    conn
    |> Auth.delete_session_cookie()
    |> send_resp(:no_content, "")
  end

  # The native client that started the sign-in, or the browser flow.
  defp client(%{"native" => %{"client_id" => client_id}}), do: client_id
  defp client(_transaction), do: "browser"

  # Only a path on this origin, so the sign-in can't be turned into an open
  # redirect. Browsers read `//host` and `/\host` as other hosts, and drop
  # tabs and newlines first, so those and other controls are refused too.
  @local_path ~r{\A/(?![/\\])[^\x00-\x20\\]*\z}

  defp return_to(path) when is_binary(path) do
    if Regex.match?(@local_path, path), do: path, else: "/"
  end

  defp return_to(_path), do: "/"

  defp with_query(url, query) do
    uri = URI.parse(url)

    URI.to_string(%{
      uri
      | query: URI.encode_query(URI.decode_query(uri.query || "", Map.new(query)))
    })
  end
end
