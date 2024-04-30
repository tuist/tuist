defmodule TuistCloudWeb.AuthenticationPlug do
  import Plug.Conn
  use TuistCloudWeb, :controller

  @moduledoc """
  A plug that deals with authentication of requests.
  """
  def init(:load_authenticated_subject = opts), do: opts
  def init({:require_authentication, _} = opts), do: opts

  def call(conn, :load_authenticated_subject) do
    token = TuistCloudWeb.Authentication.get_token(conn)

    if token do
      case TuistCloud.Authentication.authenticated_subject(token) do
        {:project, project} ->
          conn |> TuistCloudWeb.Authentication.put_authenticated_project(project)

        {:user, user} ->
          conn |> TuistCloudWeb.Authentication.put_authenticated_user(user)

        nil ->
          conn
      end
    else
      conn
    end
  end

  def call(conn, {:require_authentication, opts}) do
    response_type = opts |> Keyword.get(:response_type, :open_api)

    if TuistCloudWeb.Authentication.authenticated?(conn) do
      conn
    else
      case response_type do
        :open_api ->
          conn
          |> put_status(401)
          |> json(%{message: "You need to be authenticated to access this resource"})
          |> halt()
      end
    end
  end
end
