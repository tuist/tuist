defmodule TuistCloudWeb.AutoRedirectToProjectPlug do
  @moduledoc """
  This plub redirects the user to a project or the get started page automatically.
  """
  import Plug.Conn
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Projects

  def init(opts), do: opts

  def call(%{request_path: "/", state: state} = conn, _opts)
      when state in [:unset] do
    user = Authentication.current_user(conn)
    project = user |> project_to_redirect_to()

    if project do
      project_path = "/#{project.handle}"
      redirect(conn, to: project_path) |> halt()
    else
      redirect(conn, to: ~p"/get-started") |> halt()
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
