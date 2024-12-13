defmodule TuistWeb.AuthenticationPlug do
  import Plug.Conn
  use TuistWeb, :controller

  @moduledoc """
  A plug that deals with authentication of requests.
  """
  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistWeb.Headers
  alias Tuist.Projects
  alias TuistWeb.WarningsHeaderPlug
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  def init(:load_authenticated_subject = opts), do: opts
  def init({:require_authentication, _} = opts), do: opts

  def call(conn, :load_authenticated_subject) do
    token = TuistWeb.Authentication.get_app_installation_token_for_repository(conn)

    if token do
      conn |> get_authenticated_subject(token)
    else
      conn
    end
  end

  def call(conn, {:require_authentication, opts}) do
    response_type = opts |> Keyword.get(:response_type, :open_api)

    if TuistWeb.Authentication.authenticated?(conn) do
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
    case Tuist.Authentication.authenticated_subject(token) do
      %Project{} = project ->
        %{account: account} = Projects.get_project_account_by_project_id(project.id)

        cli_version = Headers.get_cli_version(conn)

        conn =
          if token |> Projects.legacy_token?() and not is_nil(cli_version) and
               cli_version >= Version.parse!("4.21.0") do
            conn
            |> WarningsHeaderPlug.put_warning(
              "The project token you are using is deprecated. Please create a new token by running `tuist projects token create #{account.name}/#{project.name}."
            )
          else
            conn
          end

        conn |> TuistWeb.Authentication.put_current_project(project)

      %User{} = user ->
        conn |> TuistWeb.Authentication.put_current_user(user)

      %AuthenticatedAccount{} = authenticated_account ->
        conn |> TuistWeb.Authentication.put_current_authenticated_account(authenticated_account)

      nil ->
        conn
    end
  end
end
