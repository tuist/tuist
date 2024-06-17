defmodule TuistCloudWeb.Authorization do
  @moduledoc """
  A module that provides functions for authorizing requests.
  """
  alias TuistCloudWeb.Authentication
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
    user = Authentication.current_user(conn)

    require_user_can_read_project(%{user: user, owner_handle: owner, project_handle: project})

    conn
  end

  def require_user_can_read_project(%{
        user: user,
        owner_handle: owner_handle,
        project_handle: project_handle
      }) do
    project = Projects.get_project_by_account_and_project_name(owner_handle, project_handle)

    if is_nil(project) or not TuistCloud.Authorization.can(user, :read, project, :dashboard) do
      raise TuistCloudWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end
  end
end
