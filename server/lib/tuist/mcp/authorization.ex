defmodule Tuist.MCP.Authorization do
  @moduledoc false

  alias Tuist.Projects

  def authorize_project_id(project_id, subject) do
    accessible = Projects.list_accessible_projects(subject, preload: [:account])
    accessible_ids = MapSet.new(accessible, & &1.id)

    if MapSet.member?(accessible_ids, project_id) do
      :ok
    else
      {:error, -32_602, "You do not have access to this resource."}
    end
  end

  def get_authorized_project(account_handle, project_handle, subject) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    if is_nil(project) do
      {:error, -32_602, "Project not found: #{account_handle}/#{project_handle}"}
    else
      accessible = Projects.list_accessible_projects(subject, preload: [:account])
      accessible_ids = MapSet.new(accessible, & &1.id)

      if MapSet.member?(accessible_ids, project.id) do
        {:ok, project}
      else
        {:error, -32_602, "You do not have access to project: #{account_handle}/#{project_handle}"}
      end
    end
  end
end
