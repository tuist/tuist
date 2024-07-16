defmodule TuistWeb.AutoRedirectToProjectPlug do
  @moduledoc """
  This plub redirects the user to a project or the get started page automatically.
  """
  import Plug.Conn
  use TuistWeb, :controller
  alias TuistWeb.Authentication
  alias Tuist.Projects

  def init(opts), do: opts

  def call(%{request_path: "/", state: state} = conn, _opts)
      when state in [:unset] do
    current_user = Authentication.current_user(conn)
    project = current_user |> project_to_redirect_to()

    if project do
      project_path = "/#{project.handle}"
      conn |> redirect(to: project_path) |> halt()
    else
      conn |> redirect(to: "/#{current_user.account.name}/projects") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp project_to_redirect_to(user) do
    if is_nil(user.last_visited_project_id) do
      Projects.get_all_project_accounts(user) |> List.first()
    else
      Projects.get_project_account_by_project_id(user.last_visited_project_id)
    end
  end
end
