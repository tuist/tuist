defmodule TuistCloudWeb.Authorization do
  @moduledoc """
  A module that provides functions for authorizing requests.
  """
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Accounts
  alias TuistCloud.Projects

  @doc """
  Used for project routes to ensure a user can read the project.
  """
  def require_user_can_read_project(
        %{
          path_params: %{
            "owner" => owner,
            "project" => project
          }
        } = conn,
        _opts
      ) do
    project = Projects.get_project_by_account_and_project_name(owner, project)
    account = Accounts.get_account_by_id(project.account_id)
    user = Authentication.current_user(conn)

    if not TuistCloud.Authorization.can(user, :read, account, :project) do
      raise TuistCloudWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end

    conn
  end
end
