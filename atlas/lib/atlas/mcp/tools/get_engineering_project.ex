defmodule Atlas.MCP.Tools.GetEngineeringProject do
  @moduledoc "Fetches an engineering project by id."

  use Atlas.MCP.Tool,
    name: "get_engineering_project",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "name" => %{"type" => "string"},
            "description" => %{"type" => ["string", "null"]},
            "visibility" => %{"type" => "string"},
            "domain_ids" => %{"type" => "array", "items" => %{"type" => "string"}},
            "repositories" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "required" => ["id", "name", "description", "visibility", "domain_ids", "repositories"],
          "additionalProperties" => false
        }
      },
      "required" => ["project"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Fetch an Engineering project by id."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        {:ok,
         %{
           "project" => %{
             "id" => project.id,
             "name" => project.name,
             "description" => project.description,
             "visibility" => to_string(project.visibility),
             "domain_ids" => Enum.map(project.domains, & &1.id),
             "repositories" => Enum.map(project.github_repositories, fn r -> "#{r.owner}/#{r.name}" end)
           }
         }}

      {:error, :not_found} ->
        {:error, "Project not found."}
    end
  end
end
