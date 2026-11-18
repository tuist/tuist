defmodule TuistWeb.BrowserSession do
  @moduledoc """
  Cookie sessions with browser credentials isolated from ordinary session writes.

  The dedicated signed cookie is changed only by explicit authentication actions.
  HTTP and LiveView socket session reads overlay it onto the ordinary session,
  so a late preference, flash or redirect response cannot replace a login.
  Legacy session credentials remain readable when no dedicated cookie exists.
  Explicit authentication actions always establish or update that authority.
  """

  @behaviour Plug.Session.Store

  import Plug.Conn

  alias Plug.Session.COOKIE
  alias Tuist.Accounts.UserToken

  @cookie Application.compile_env(:tuist, :session_cookie_key, "_tuist_key") <> "_auth"
  @remember_cookie "_tuist_web_user_remember_me"
  @keys ["user_token", "live_socket_id", "auth_method"]
  @cookie_options [
    path: "/",
    http_only: true,
    same_site: "Lax",
    secure: Application.compile_env(:tuist, :session_cookie_secure, false)
  ]

  @impl true
  def init(opts), do: COOKIE.init(opts)

  @impl true
  def get(conn, cookie, opts) do
    {id, session} = COOKIE.get(conn, cookie, opts)
    {id, Map.merge(Map.drop(session, @keys), authentication(conn, session))}
  end

  # Keep a compatibility snapshot for older replicas during a rolling deploy.
  # Once the dedicated cookie exists, get/3 never trusts this snapshot again.
  @impl true
  def put(conn, id, session, opts), do: COOKIE.put(conn, id, session, opts)

  @impl true
  def delete(conn, id, opts), do: COOKIE.delete(conn, id, opts)

  def fetch(conn) do
    put_snapshot(conn, authentication(conn, get_session(conn)))
  end

  def put_authentication(conn, token, auth_method, remember? \\ false) do
    credentials = %{
      "user_token" => token,
      "live_socket_id" => "users_sessions:#{Base.url_encode64(token)}",
      "auth_method" => auth_method
    }

    conn
    |> put_snapshot(credentials)
    |> put_authentication_cookie(credentials, remember?)
  end

  def clear_authentication(conn) do
    # Deleting the cookie would allow a late legacy-session response to become
    # authoritative again. Retain a signed-out marker for every token's lifetime.
    conn
    |> put_snapshot(%{})
    |> put_authentication_cookie(%{}, true)
  end

  defp put_authentication_cookie(conn, credentials, persistent?) do
    lifetime = UserToken.session_absolute_seconds()
    # Plug's sign: true defaults to a one-day signature when max_age is absent.
    # Session-only browser retention must not shorten the server's token lifetime.
    signed =
      Plug.Crypto.sign(conn.secret_key_base, @cookie <> "_cookie", credentials, keys: Plug.Keys, max_age: lifetime)

    opts = if persistent?, do: [max_age: lifetime] ++ @cookie_options, else: @cookie_options
    put_resp_cookie(conn, @cookie, signed, opts)
  end

  defp authentication(conn, session) do
    conn = fetch_cookies(conn, signed: [@cookie, @remember_cookie])

    cond do
      Map.has_key?(conn.req_cookies, @cookie) ->
        case conn.cookies[@cookie] do
          %{"user_token" => token} = credentials when is_binary(token) -> Map.take(credentials, @keys)
          _ -> %{}
        end

      is_binary(session["user_token"]) ->
        Map.take(session, @keys)

      is_binary(conn.cookies[@remember_cookie]) ->
        token = conn.cookies[@remember_cookie]
        %{"user_token" => token, "live_socket_id" => "users_sessions:#{Base.url_encode64(token)}"}

      true ->
        %{}
    end
  end

  defp put_snapshot(conn, credentials) do
    Enum.reduce(@keys, conn, fn key, conn ->
      case {get_session(conn, key), credentials[key]} do
        {value, value} -> conn
        {_, nil} -> delete_session(conn, key)
        {_, value} -> put_session(conn, key, value)
      end
    end)
  end
end
