defmodule Atlas.MCP.Tools.GetProjectErrorDsn do
  @moduledoc "Returns the Sentry-compatible DSN for a project."

  use Atlas.MCP.Tool,
    name: "get_project_error_dsn",
    schema: %{
      "type" => "object",
      "required" => ["project_id"],
      "properties" => %{"project_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "object"}},
      "required" => ["key"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description,
    do:
      "Return the current Sentry-compatible Data Source Name for a project. Lazily provisions one if the project has none."

  def execute(conn, %{"project_id" => project_id}) do
    user = Tool.current_user(conn)

    case Projects.fetch_visible_project(project_id, user) do
      {:ok, project} ->
        case Errors.primary_project_key(project) do
          nil -> {:error, "DSN unavailable for project."}
          key -> {:ok, %{"key" => EngineeringSerializers.project_key(key)}}
        end

      {:error, :not_found} ->
        {:error, "Project not found."}
    end
  end
end
