defmodule Atlas.MCP.Tools.DeleteEngineeringProject do
  @moduledoc "Deletes an engineering project."

  use Atlas.MCP.Tool,
    name: "delete_engineering_project",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted_project" => %{"type" => "object"}},
      "required" => ["deleted_project"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Delete an Engineering project."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        snapshot = EngineeringSerializers.project(project)

        case Projects.delete_project(project) do
          {:ok, _} -> {:ok, %{"deleted_project" => snapshot}}
          {:error, changeset} -> {:error, "Could not delete project: #{Tool.format_changeset_errors(changeset)}"}
        end

      {:error, :not_found} ->
        {:error, "Project not found."}
    end
  end
end
