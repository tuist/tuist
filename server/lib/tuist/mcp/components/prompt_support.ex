defmodule Tuist.MCP.Components.PromptSupport do
  @moduledoc false

  alias Tuist.Projects

  def resolve_project_handles(arguments) do
    case {Map.get(arguments, "account_handle"), Map.get(arguments, "project_handle")} do
      {ah, ph} when is_binary(ah) and is_binary(ph) -> {ah, ph}
      _ -> {nil, nil}
    end
  end

  def resolve_project_metadata(account_handle, project_handle)
      when is_binary(account_handle) and is_binary(project_handle) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      nil -> %{default_branch: nil, build_system: nil}
      project -> %{default_branch: project.default_branch, build_system: project.build_system}
    end
  end

  def resolve_project_metadata(_account_handle, _project_handle), do: %{default_branch: nil, build_system: nil}

  def resolve_default_branch(account_handle, project_handle) do
    resolve_project_metadata(account_handle, project_handle).default_branch
  end
end
