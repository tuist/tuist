defmodule TuistWeb.Authorization do
  @moduledoc """
  A module that provides functions for authorizing requests.
  """
  alias TuistWeb.Authentication
  alias Tuist.Projects

  @doc """
  Used for project routes to ensure a user can read the project.
  """
  def require_user_can_read_project(
        %{
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle
          }
        } = conn,
        _opts
      ) do
    user = Authentication.current_user(conn)

    require_user_can_read_project(%{
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    })

    conn
  end

  def require_user_can_read_project(%{
        user: user,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    if is_nil(project) or not Tuist.Authorization.can(user, :read, project, :dashboard) do
      raise TuistWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end
  end
end
