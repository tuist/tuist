defmodule Atlas.MCP.Tools.UnlinkProjectRepository do
  @moduledoc "Removes a repository link from a project."

  use Atlas.MCP.Tool,
    name: "unlink_project_repository",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "repository_id"],
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "repository_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{"type" => "object"},
        "unlinked_repository" => %{"type" => "object"}
      },
      "required" => ["project", "unlinked_repository"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Remove a GitHub repository link from an Engineering project."

  def execute(conn, %{"project_id" => project_id, "repository_id" => repository_id}) do
    user = Tool.current_user(conn)

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, repository} <- Projects.delete_repository_from_project(project, repository_id) do
      {:ok,
       %{
         "project" => EngineeringSerializers.project(Projects.get_project!(project.id)),
         "unlinked_repository" => EngineeringSerializers.repository(repository)
       }}
    else
      {:error, :not_found} -> {:error, "Project or repository not found."}
    end
  end
end
