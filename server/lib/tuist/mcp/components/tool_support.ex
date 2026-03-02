defmodule Tuist.MCP.Components.ToolSupport do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Tuist.MCP.Authorization
  alias Tuist.Projects

  def authenticated_subject(assigns) when is_map(assigns) do
    Authorization.authenticated_subject(assigns)
  end

  def authorize_project(frame, project, action, category, message \\ "You do not have access to this resource.") do
    if Authorization.authorize(authenticated_subject(frame.assigns), action, project, category) do
      :ok
    else
      invalid_params(message, frame)
    end
  end

  def load_resource({:ok, resource}, _message, _frame), do: {:ok, resource}
  def load_resource({:error, :not_found}, message, frame), do: invalid_params(message, frame)
  def load_resource(_result, message, frame), do: invalid_params(message, frame)

  def load_project(project_id, frame, message \\ "Project not found.") do
    case Projects.get_project_by_id(project_id) do
      nil -> invalid_params(message, frame)
      project -> {:ok, project}
    end
  end

  def authorize_project_by_id(
        frame,
        project_id,
        action,
        category,
        unauthorized_message \\ "You do not have access to this resource.",
        not_found_message \\ "Project not found."
      ) do
    with {:ok, project} <- load_project(project_id, frame, not_found_message),
         :ok <- authorize_project(frame, project, action, category, unauthorized_message) do
      {:ok, project}
    end
  end

  def load_project_by_handle(account_handle, project_handle, frame) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      nil -> invalid_params("Project not found: #{account_handle}/#{project_handle}", frame)
      project -> {:ok, project}
    end
  end

  def load_and_authorize_project_by_handle(account_handle, project_handle, frame, action, category, unauthorized_message) do
    with {:ok, project} <- load_project_by_handle(account_handle, project_handle, frame),
         :ok <- authorize_project(frame, project, action, category, unauthorized_message) do
      {:ok, project}
    end
  end

  def invalid_params(message, frame) do
    {:error, Error.protocol(:invalid_params, %{message: message}), frame}
  end
end
