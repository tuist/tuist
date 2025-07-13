defmodule TuistWeb.DashboardController do
  use TuistWeb, :controller

  alias Tuist.Projects

  def dashboard(%{assigns: %{current_user: current_user}} = conn, _params) do
    project_account =
      if is_nil(current_user.last_visited_project_id) do
        current_user |> Projects.get_all_project_accounts() |> List.first()
      else
        Projects.get_project_account_by_project_id(current_user.last_visited_project_id)
      end

    if project_account do
      conn
      |> redirect(to: ~p"/#{project_account.account.name}/#{project_account.project.name}")
      |> halt()
    else
      conn |> redirect(to: ~p"/#{current_user.account.name}/projects") |> halt()
    end
  end
end
