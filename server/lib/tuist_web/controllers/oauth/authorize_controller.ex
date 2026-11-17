defmodule TuistWeb.Oauth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use TuistWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizationSuccess
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner
  alias Tuist.Accounts.UserToken
  alias Tuist.OAuth.Clients
  alias TuistWeb.Errors.BadRequestError

  require Logger

  @max_state_length 10_000

  plug TuistWeb.Plugs.OAuthRequestObjectPlug when action == :authorize

  def authorize(%Plug.Conn{assigns: %{current_user: %Tuist.Accounts.User{} = current_user}} = conn, _params) do
    # Boruta reads the request from the query alone, so the checks here must
    # too: `params` also merges in the body of the consent POST, where the
    # body wins.
    query = conn.query_params
    :ok = validate_state_length!(query)

    case query["response_type"] do
      "code" ->
        # The authorization code, and the tokens exchanged for it, carry the
        # SSO sign-in of this session (see `Tuist.OAuth.TokenGenerator`).
        resource_owner = %ResourceOwner{
          sub: to_string(current_user.id),
          username: current_user.email,
          extra_claims: UserToken.sso_claims(conn.assigns[:current_user_session])
        }

        # Tuist Guild is a public native client: its ID is public and its
        # redirects can be claimed by other apps on the device, so the ID
        # proves nothing about who is asking (RFC 8252, section 8.6). Its
        # sign-ins act as the signed-in user, so each one needs the person to
        # approve it on the page `preauthorize_success/2` renders, which posts
        # back here with the same query.
        if query["client_id"] == Clients.guild_client_id() do
          conn
          |> put_private(:oauth_consent, {consent(conn), resource_owner})
          |> Oauth.preauthorize(resource_owner, __MODULE__)
        else
          Oauth.authorize(conn, resource_owner, __MODULE__)
        end

      _ ->
        render_authorize_error(conn, %Error{
          status: :bad_request,
          error: :unsupported_response_type,
          error_description: "Only the code response type is supported."
        })
    end
  end

  def authorize(%Plug.Conn{} = conn, _params) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect_to_login()
  end

  def authorize_with_github(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:user_return_to, oauth_return_url)
    |> redirect(to: "/users/auth/github")
    |> halt()
  end

  def authorize_with_google(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:user_return_to, oauth_return_url)
    |> redirect(to: "/users/auth/google")
    |> halt()
  end

  def authorize_with_apple(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:user_return_to, oauth_return_url)
    |> redirect(to: "/users/auth/apple")
    |> halt()
  end

  @impl AuthorizeApplication
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect_url = AuthorizeResponse.redirect_to_url(response)
    redirect(conn, external: redirect_url)
  end

  @impl AuthorizeApplication
  def authorize_error(%Plug.Conn{} = conn, %Error{status: :unauthorized} = error) do
    Logger.error("OAuth authorize unauthorized: #{inspect(error)}")

    if conn.assigns[:current_user] do
      render_authorize_error(conn, error)
    else
      redirect_to_login(conn)
    end
  end

  @impl AuthorizeApplication
  def authorize_error(%Plug.Conn{} = conn, %Error{} = error) do
    Logger.error("OAuth authorize error: #{inspect(error)}")

    if conn.assigns[:current_user] do
      render_authorize_error(conn, error)
    else
      redirect_to_login(conn)
    end
  end

  @impl AuthorizeApplication
  # Only Tuist Guild's requests are preauthorized, so Boruta has validated the
  # client, redirect URI and PKCE challenge before any of these redirect.
  def preauthorize_success(conn, %AuthorizationSuccess{scope: scope} = authorization) when scope not in [nil, ""] do
    redirect_error(conn, authorization, :invalid_scope, "Tuist Guild requests no scopes.")
  end

  def preauthorize_success(%Plug.Conn{private: %{oauth_consent: {:deny, _}}} = conn, authorization) do
    redirect_error(conn, authorization, :access_denied, "The sign-in was cancelled.")
  end

  def preauthorize_success(%Plug.Conn{private: %{oauth_consent: {:allow, resource_owner}}} = conn, _authorization) do
    Oauth.authorize(conn, resource_owner, __MODULE__)
  end

  def preauthorize_success(conn, %AuthorizationSuccess{client: client}) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_view(TuistWeb.Oauth.AuthorizeHTML)
    |> render(:consent,
      client_name: client.name,
      email: conn.assigns.current_user.email,
      action: "/oauth2/authorize?" <> conn.query_string,
      head_title: dgettext("dashboard_auth", "Sign in to %{client} · Tuist", client: client.name)
    )
  end

  @impl AuthorizeApplication
  def preauthorize_error(conn, %Error{} = error), do: authorize_error(conn, error)

  defp consent(%Plug.Conn{method: "POST", body_params: %{"consent" => "allow"}}), do: :allow
  defp consent(%Plug.Conn{method: "POST"}), do: :deny
  defp consent(_conn), do: :ask

  defp redirect_error(conn, %AuthorizationSuccess{} = authorization, error, description) do
    render_authorize_error(conn, %Error{
      status: :bad_request,
      error: error,
      error_description: description,
      format: :query,
      redirect_uri: authorization.redirect_uri,
      state: authorization.state
    })
  end

  defp render_authorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect(conn, external: Error.redirect_to_url(error))
  end

  defp render_authorize_error(conn, error) do
    conn
    |> put_status(error_status_code(error.status))
    |> json(%{
      error: to_string(error.error),
      error_description: error.error_description
    })
  end

  defp error_status_code(:bad_request), do: 400
  defp error_status_code(:unauthorized), do: 401
  defp error_status_code(:internal_server_error), do: 500
  defp error_status_code(_), do: 400

  defp redirect_to_login(conn) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect(to: ~p"/users/log_in")
    |> halt()
  end

  defp validate_state_length!(%{"state" => state}) when byte_size(state) > @max_state_length do
    raise BadRequestError, "The state parameter must not exceed #{@max_state_length} characters."
  end

  defp validate_state_length!(_params), do: :ok
end
