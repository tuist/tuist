defmodule Tuist.MCP.Components.ToolSupport do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.Projects

  def authenticated_subject(assigns) when is_map(assigns) do
    Authorization.authenticated_subject(assigns)
  end

  def authorize_project(assigns, project, action, category, message \\ "You do not have access to this resource.") do
    if Authorization.authorize(authenticated_subject(assigns), action, project, category) do
      :ok
    else
      {:error, message}
    end
  end

  def load_resource({:ok, resource}, _message), do: {:ok, resource}
  def load_resource({:error, :not_found}, message), do: {:error, message}
  def load_resource(_result, message), do: {:error, message}

  def load_project(project_id, message \\ "Project not found.") do
    case Projects.get_project_by_id(project_id) do
      nil -> {:error, message}
      project -> {:ok, project}
    end
  end

  def authorize_project_by_id(
        assigns,
        project_id,
        action,
        category,
        unauthorized_message \\ "You do not have access to this resource.",
        not_found_message \\ "Project not found."
      ) do
    with {:ok, project} <- load_project(project_id, not_found_message),
         :ok <- authorize_project(assigns, project, action, category, unauthorized_message) do
      {:ok, project}
    end
  end

  def load_project_by_handle(account_handle, project_handle) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      nil -> {:error, "Project not found: #{account_handle}/#{project_handle}"}
      project -> {:ok, project}
    end
  end

  def load_and_authorize_project_by_handle(account_handle, project_handle, assigns, action, category, unauthorized_message) do
    with {:ok, project} <- load_project_by_handle(account_handle, project_handle),
         :ok <- authorize_project(assigns, project, action, category, unauthorized_message) do
      {:ok, project}
    end
  end

  def resolve_and_authorize_project(
        %{"account_handle" => account_handle, "project_handle" => project_handle},
        assigns,
        action,
        category
      )
      when is_binary(account_handle) and is_binary(project_handle) do
    load_and_authorize_project_by_handle(
      account_handle,
      project_handle,
      assigns,
      action,
      category,
      "You do not have access to project: #{account_handle}/#{project_handle}"
    )
  end

  def resolve_and_authorize_project(_arguments, _assigns, _action, _category) do
    {:error, "Provide account_handle and project_handle."}
  end

  def invalid_params(message) do
    {:error, message}
  end

  @max_page_size 100
  @default_page_size 20

  def page(arguments) do
    case Map.get(arguments, "page") do
      value when is_integer(value) and value > 0 -> value
      _ -> 1
    end
  end

  def page_size(arguments) do
    case Map.get(arguments, "page_size") do
      value when is_integer(value) and value > 0 -> min(value, @max_page_size)
      _ -> @default_page_size
    end
  end

  def pagination_metadata(meta) do
    %{
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      total_count: meta.total_count,
      total_pages: meta.total_pages,
      current_page: meta.current_page,
      page_size: meta.page_size
    }
  end

  def json_response(data) do
    EMCP.Tool.response([%{"type" => "text", "text" => Jason.encode!(data)}])
  end
end
