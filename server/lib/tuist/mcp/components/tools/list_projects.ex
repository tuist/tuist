defmodule Tuist.MCP.Components.Tools.ListProjects do
  @moduledoc """
  List all projects accessible to the authenticated subject.
  """

  use Tuist.MCP.Tool,
    name: "list_projects",
    title: "List Projects",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "projects" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "name" => %{"type" => "string"},
              "account_handle" => %{"type" => "string"},
              "full_handle" => %{"type" => "string"},
              "build_system" => %{"type" => "string", "enum" => ["xcode", "gradle"]},
              "default_branch" => %{"type" => "string"}
            },
            "required" => [
              "id",
              "name",
              "account_handle",
              "full_handle",
              "build_system",
              "default_branch"
            ],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["projects"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Projects

  @impl EMCP.Tool
  def description, do: "List all projects accessible to the authenticated subject."

  @impl EMCP.Tool
  def call(conn, _args) do
    subject = Authorization.authenticated_subject(conn.assigns)
    projects = Projects.list_accessible_projects(subject, preload: [:account])

    data = %{
      projects:
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
    }

    MCPTool.json_response(data, __MODULE__)
  end
end
