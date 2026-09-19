defmodule Atlas.MCP.Tools.LinkProjectRepository do
  @moduledoc "Links a GitHub repository to a project."

  use Atlas.MCP.Tool,
    name: "link_project_repository",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "owner", "name"],
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "owner" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{"type" => "object"},
        "repository" => %{"type" => "object"}
      },
      "required" => ["project", "repository"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Link a GitHub repository to an Engineering project."

  def execute(conn, %{"project_id" => project_id} = args) do
    user = Tool.current_user(conn)
    attrs = Map.take(args, ["owner", "name", "visibility"])

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, repository} <- Projects.create_repository_for_project(project, attrs) do
      {:ok,
       %{
         "project" => EngineeringSerializers.project(Projects.get_project!(project.id)),
         "repository" => EngineeringSerializers.repository(repository)
       }}
    else
      {:error, :not_found} -> {:error, "Project not found."}
      {:error, changeset} -> {:error, "Could not link repository: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
