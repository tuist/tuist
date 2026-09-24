defmodule AtlasWeb.Oauth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use AtlasWeb, :controller

  alias Atlas.Users.User
  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner

  require Logger

  def authorize(%Plug.Conn{assigns: %{current_user: %User{} = user}} = conn, _params) do
    Oauth.authorize(
      conn,
      %ResourceOwner{sub: to_string(user.id), username: user.email},
      __MODULE__
    )
  end

  def authorize(%Plug.Conn{} = conn, _params) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect(to: ~p"/login")
    |> halt()
  end

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

  @impl AuthorizeApplication
  def preauthorize_success(_conn, _response), do: :ok

  @impl AuthorizeApplication
  def preauthorize_error(_conn, _response), do: :ok

  defp error_status(:bad_request), do: 400
  defp error_status(:unauthorized), do: 401
  defp error_status(:internal_server_error), do: 500
  defp error_status(_), do: 400
end
