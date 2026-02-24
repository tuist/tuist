defmodule TuistWeb.Oauth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use TuistWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner
  alias TuistWeb.Errors.BadRequestError

  require Logger

  @max_state_length 10_000

  def authorize(%Plug.Conn{assigns: %{current_user: %Tuist.Accounts.User{} = current_user}} = conn, params) do
    :ok = validate_state_length!(params)

    Oauth.authorize(
      conn,
      %ResourceOwner{sub: to_string(current_user.id), username: current_user.email},
      __MODULE__
    )
  end

  def authorize(%Plug.Conn{} = conn, _params) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect_to_login()
  end

  def authorize_with_github(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:oauth_return_to, oauth_return_url)
    |> redirect(to: "/users/auth/github")
    |> halt()
  end

  def authorize_with_google(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:oauth_return_to, oauth_return_url)
    |> redirect(to: "/users/auth/google")
    |> halt()
  end

  def authorize_with_apple(conn, params) do
    oauth_return_url = "/oauth2/authorize?" <> URI.encode_query(params)

    conn
    |> put_session(:oauth_return_to, oauth_return_url)
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
    redirect_to_login(conn)
  end

  @impl AuthorizeApplication
  def authorize_error(%Plug.Conn{} = conn, %Error{} = error) do
    Logger.error("OAuth authorize error: #{inspect(error)}")
    redirect_to_login(conn)
  end

  @impl AuthorizeApplication
  def preauthorize_success(_conn, _response), do: :ok

  @impl AuthorizeApplication
  def preauthorize_error(_conn, _response), do: :ok

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
