defmodule Atlas.MCP.Tools.UpdateEngineeringProject do
  @moduledoc "Updates an engineering project."

  use Atlas.MCP.Tool,
    name: "update_engineering_project",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"project" => %{"type" => "object"}},
      "required" => ["project"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Update an Engineering project."

  def execute(conn, %{"id" => id} = args) do
    user = Tool.current_user(conn)
    attrs = Map.take(args, ["name", "description", "visibility"])

    with {:ok, project} <- Projects.fetch_visible_project(id, user),
         {:ok, updated} <- Projects.update_project(project, attrs) do
      {:ok, %{"project" => EngineeringSerializers.project(Projects.get_project!(updated.id))}}
    else
      {:error, :not_found} -> {:error, "Project not found."}
      {:error, changeset} -> {:error, "Could not update project: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
