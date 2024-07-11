defmodule TuistCloudWeb.AuthenticationPlug do
  import Plug.Conn
  use TuistCloudWeb, :controller

  @moduledoc """
  A plug that deals with authentication of requests.
  """
  alias TuistCloud.Projects
  alias TuistCloudWeb.WarningsHeaderPlug
  alias TuistCloud.Accounts.User
  alias TuistCloud.Projects.Project
  def init(:load_authenticated_subject = opts), do: opts
  def init({:require_authentication, _} = opts), do: opts

  def call(conn, :load_authenticated_subject) do
    token = TuistCloudWeb.Authentication.get_token(conn)

    if token do
      conn |> get_authenticated_subject(token)
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
          |> put_status(:unauthorized)
          |> json(%{message: "You need to be authenticated to access this resource."})
          |> halt()
      end
    end
  end

  defp get_authenticated_subject(conn, token) do
    case TuistCloud.Authentication.authenticated_subject(token) do
      %Project{} = project ->
        %{account: account} = Projects.get_project_account_by_project_id(project.id)

        conn =
          if token |> Projects.legacy_token?() do
            conn
            |> WarningsHeaderPlug.put_warning(
              "The project token you are using is deprecated. Please create a new token by running `tuist projects token create #{account.name}/#{project.name}."
            )
          else
            conn
          end

        conn |> TuistCloudWeb.Authentication.put_current_project(project)

      %User{} = user ->
        conn |> TuistCloudWeb.Authentication.put_current_user(user)

      nil ->
        conn
    end
  end
end
