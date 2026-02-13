defmodule Tuist.MCP.Tools.ListProjects do
  @moduledoc false

  alias Tuist.Projects

  def name, do: "list_projects"

  def definition do
    %{
      name: name(),
      description: "List all projects accessible to the authenticated user.",
      inputSchema: %{
        type: "object",
        properties: %{}
      }
    }
  end

  def call(_arguments, subject) do
    projects = Projects.list_accessible_projects(subject, preload: [:account])

    data =
      Enum.map(projects, fn project ->
        %{
          id: project.id,
          name: project.name,
          account_handle: project.account.name,
          full_handle: "#{project.account.name}/#{project.name}"
        }
      end)

    {:ok, %{content: [%{type: "text", text: Jason.encode!(data)}]}}
  end
end
