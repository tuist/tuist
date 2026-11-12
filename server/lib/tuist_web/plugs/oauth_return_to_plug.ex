defmodule TuistWeb.Plugs.OAuthReturnToPlug do
  @moduledoc false

  import Plug.Conn

  alias TuistWeb.Authentication

  @state_prefix "tuist-return-v1:"
  @cookie_options [
    path: "/users/auth",
    same_site: "Lax",
    secure: Application.compile_env(:tuist, :session_cookie_secure, false)
  ]

  def init(opts), do: opts

  # Version the generated state in both the outgoing redirect and its CSRF
  # cookie. Ueberauth still generates the random value and validates equality.
  # The version distinguishes old in-flight flows without a destination binding.
  def call(conn, _opts) do
    return_to = Map.get(conn.params, "return_to", get_session(conn, :user_return_to))

    register_before_send(conn, fn conn ->
      case {conn.resp_cookies["ueberauth.state_param"], get_resp_header(conn, "location")} do
        {%{value: state, same_site: same_site} = cookie, [location]} when is_binary(state) and state != "" ->
          state = version_state(state)
          uri = URI.parse(location)
          query = uri.query |> URI.decode_query() |> Map.put("state", state) |> URI.encode_query()

          conn
          |> put_resp_header("location", URI.to_string(%{uri | query: query}))
          |> put_resp_cookie("ueberauth.state_param", state, cookie |> Map.delete(:value) |> Map.to_list())
          |> put(state, return_to, same_site: same_site)

        _ ->
          conn
      end
    end)
  end

  def version_state(state), do: @state_prefix <> state

  def put(conn, state, return_to, opts \\ []) do
    put_resp_cookie(
      conn,
      cookie_name(state),
      %{return_to: Authentication.session_return_to(return_to)},
      Keyword.merge([sign: true, max_age: 600] ++ @cookie_options, opts)
    )
  end

  # Call only after the provider's state and identity have been verified.
  # New flows fail closed on a missing/invalid binding. Pre-upgrade state has
  # no version prefix, so retain its legacy destination after provider validation.
  def restore(conn, %{"state" => state}) when is_binary(state) do
    name = cookie_name(state)
    conn = fetch_cookies(conn, signed: [name])

    if String.starts_with?(state, @state_prefix) or Map.has_key?(conn.req_cookies, name) do
      return_to = get_in(conn.cookies, [name, :return_to])

      conn
      |> delete_resp_cookie(name, @cookie_options)
      |> delete_session(:oauth_return_to)
      |> Authentication.put_return_to(:user_return_to, return_to)
    else
      conn
    end
  end

  def restore(conn, _params), do: conn

  defp cookie_name(state), do: "_tuist_oauth_return_" <> Base.url_encode64(:crypto.hash(:sha256, state), padding: false)
end
