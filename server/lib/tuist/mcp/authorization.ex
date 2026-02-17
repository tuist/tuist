defmodule Tuist.MCP.Authorization do
  @moduledoc false

  alias Tuist.Authorization
  alias Tuist.MCP.Errors
  alias Tuist.Projects

  def authorize_project_id(project_id, subject) do
    project = Projects.get_project_by_id(project_id)

    if is_nil(project) do
      Errors.invalid_params("Project not found.")
    else
      case Authorization.authorize(:test_read, subject, project) do
        :ok -> :ok
        {:error, :forbidden} -> Errors.invalid_params("You do not have access to this resource.")
      end
    end
  end

  def get_authorized_project(account_handle, project_handle, subject) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    if is_nil(project) do
      Errors.invalid_params("Project not found: #{account_handle}/#{project_handle}")
    else
      case Authorization.authorize(:test_read, subject, project) do
        :ok ->
          {:ok, project}

        {:error, :forbidden} ->
          Errors.invalid_params("You do not have access to project: #{account_handle}/#{project_handle}")
      end
    end
  end
end
