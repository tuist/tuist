defmodule Tuist.MCP.Components.Tools.ListProjects do
  @moduledoc """
  List all projects accessible to the authenticated user.
  """

  use Tuist.MCP.Tool,
    name: "list_projects",
    schema: %{
      "type" => "object",
      "properties" => %{}
    }

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Projects

  @impl EMCP.Tool
  def description, do: "List all projects accessible to the authenticated user."

  @impl EMCP.Tool
  def call(conn, _args) do
    subject = Authorization.authenticated_subject(conn.assigns)
    projects = Projects.list_accessible_projects(subject, preload: [:account])

    data =
      Enum.map(projects, fn project ->
        %{
          id: project.id,
          name: project.name,
          account_handle: project.account.name,
          full_handle: "#{project.account.name}/#{project.name}",
          build_system: to_string(project.build_system),
          default_branch: project.default_branch
        }
      end)

    MCPTool.json_response(data)
  end
end
