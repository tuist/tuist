defmodule Tuist.MCP.Components.ToolPlug do
  @moduledoc false

  defmacro __using__(opts) do
    action = Keyword.get(opts, :action, :read)
    category = Keyword.fetch!(opts, :category)

    quote bind_quoted: [action: action, category: category] do
      alias Hermes.MCP.Error
      alias Tuist.MCP.Authorization
      alias Tuist.Projects

      @mcp_authorization_action action
      @mcp_authorization_category category

      defp authenticated_subject(frame) do
        Authorization.authenticated_subject(frame.assigns)
      end

      defp authorize_project(frame, project, message \\ "You do not have access to this resource.") do
        if Authorization.authorize(
             authenticated_subject(frame),
             @mcp_authorization_action,
             project,
             @mcp_authorization_category
           ) do
          :ok
        else
          invalid_params(message, frame)
        end
      end

      defp load_resource({:ok, resource}, _message, _frame), do: {:ok, resource}
      defp load_resource({:error, :not_found}, message, frame), do: invalid_params(message, frame)
      defp load_resource(_result, message, frame), do: invalid_params(message, frame)

      defp load_project(project_id, frame, message \\ "Project not found.") do
        case Projects.get_project_by_id(project_id) do
          nil -> invalid_params(message, frame)
          project -> {:ok, project}
        end
      end

      defp authorize_project_by_id(
             frame,
             project_id,
             unauthorized_message \\ "You do not have access to this resource.",
             not_found_message \\ "Project not found."
           ) do
        with {:ok, project} <- load_project(project_id, frame, not_found_message),
             :ok <- authorize_project(frame, project, unauthorized_message) do
          {:ok, project}
        end
      end

      defp load_project_by_handle(account_handle, project_handle, frame) do
        case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
          nil -> invalid_params("Project not found: #{account_handle}/#{project_handle}", frame)
          project -> {:ok, project}
        end
      end

      defp load_and_authorize_project_by_handle(account_handle, project_handle, frame, unauthorized_message) do
        with {:ok, project} <- load_project_by_handle(account_handle, project_handle, frame),
             :ok <- authorize_project(frame, project, unauthorized_message) do
          {:ok, project}
        end
      end

      defp invalid_params(message, frame) do
        {:error, Error.protocol(:invalid_params, %{message: message}), frame}
      end
    end
  end
end
