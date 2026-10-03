defmodule Atlas.MCP.Tools.CreateEngineeringProject do
  @moduledoc "Creates an engineering project."

  use Atlas.MCP.Tool,
    name: "create_engineering_project",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
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
  def description, do: "Create an Engineering project."

  def execute(_conn, args) do
    attrs = Map.take(args, ["name", "description", "visibility"])

    case Projects.create_project(attrs) do
      {:ok, project} ->
        {:ok, %{"project" => EngineeringSerializers.project(Projects.get_project!(project.id))}}

      {:error, changeset} ->
        {:error, "Could not create project: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
