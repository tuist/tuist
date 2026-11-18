defmodule AtlasWeb.Oauth.AuthorizeController do
  @moduledoc """
  Client → Atlas OAuth authorization. A signed-in person must explicitly approve
  each authorization request on a CSRF-protected consent page before Atlas
  issues a code; a GET never issues one, so a crafted link alone cannot grant a
  third-party client the person's MCP access.
  """
  @behaviour Boruta.Oauth.AuthorizeApplication

  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Users.User
  alias AtlasWeb.Oauth.RedirectURIs
  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizationSuccess
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner

  require Logger

  # Boruta resolves `request` (an unsigned JWT) and `request_uri` (fetched over
  # HTTP on every call) into the authorization parameters. A remote request
  # object can differ between the consent page and the approval, so the person
  # could approve one client while the code goes to another; fetching it also
  # makes Atlas request arbitrary URLs. No supported client uses either.
  def authorize(%Plug.Conn{assigns: %{current_user: %User{}}, query_params: query_params} = conn, _params)
      when is_map_key(query_params, "request") or is_map_key(query_params, "request_uri") do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_request", error_description: "request and request_uri are not supported."})
  end

  def authorize(%Plug.Conn{assigns: %{current_user: %User{} = user}} = conn, _params) do
    # Both the consent page (GET) and the decision (POST) revalidate the request
    # from the query string alone. Boruta would otherwise read a `request` or
    # `request_uri` from the POST body, letting the submitted form change the
    # client, redirect, scope or PKCE challenge the person saw.
    decision = if conn.method == "POST", do: conn.body_params["decision"]

    conn
    |> Map.put(:body_params, %{})
    |> assign(:oauth_decision, decision)
    |> Oauth.preauthorize(resource_owner(user), __MODULE__)
  end

  def authorize(%Plug.Conn{} = conn, params) do
    login_path = if params["provider"] == "google", do: ~p"/auth/google", else: ~p"/login"

    conn
    |> put_session(:return_to, current_path(conn))
    |> redirect(to: login_path)
    |> halt()
  end

  @impl AuthorizeApplication
  def preauthorize_success(%Plug.Conn{method: "GET"} = conn, %AuthorizationSuccess{} = authorization) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_layout(false)
    |> render(:consent,
      page_title: gettext("Authorize access"),
      client_name: authorization.client.name,
      destination: RedirectURIs.describe(authorization.redirect_uri),
      user: conn.assigns.current_user,
      action: current_path(conn)
    )
  end

  def preauthorize_success(
        %Plug.Conn{method: "POST", assigns: %{oauth_decision: "allow"}} = conn,
        %AuthorizationSuccess{} = authorization
      ) do
    user = conn.assigns.current_user

    Audit.record("oauth.client_authorized", %{
      interface: "dashboard",
      actor_id: user.id,
      actor_email: user.email,
      actor_name: user.name,
      target_type: "oauth_client",
      target_id: authorization.client.id,
      target_label: authorization.client.name,
      metadata: %{
        "redirect_destination" => RedirectURIs.describe(authorization.redirect_uri),
        "scope" => authorization.scope
      }
    })

    Oauth.authorize(conn, resource_owner(user), __MODULE__)
  end

  def preauthorize_success(%Plug.Conn{method: "POST"} = conn, %AuthorizationSuccess{} = authorization) do
    error = %Error{
      status: :unauthorized,
      error: :access_denied,
      error_description: "The resource owner denied the request.",
      format: :query,
      redirect_uri: authorization.redirect_uri,
      state: authorization.state
    }

    redirect(conn, external: Error.redirect_to_url(error))
  end

  @impl AuthorizeApplication
  def preauthorize_error(conn, %Error{} = error), do: authorize_error(conn, error)

  @impl AuthorizeApplication
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect(conn, external: AuthorizeResponse.redirect_to_url(response))
  end

  @impl AuthorizeApplication
  def authorize_error(conn, %Error{} = error) do
    Logger.error("OAuth authorize error: #{inspect(error)}")

    if error.format do
      redirect(conn, external: Error.redirect_to_url(error))
    else
      conn
      |> put_status(error_status(error.status))
      |> json(%{error: to_string(error.error), error_description: error.error_description})
    end
  end

  defp resource_owner(%User{} = user), do: %ResourceOwner{sub: to_string(user.id), username: user.email}

  defp error_status(:bad_request), do: 400
  defp error_status(:unauthorized), do: 401
  defp error_status(:internal_server_error), do: 500
  defp error_status(_), do: 400
end
