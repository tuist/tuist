defmodule Atlas.MCP.Tools.RotateProjectErrorDsn do
  @moduledoc "Rotates the Sentry-compatible DSN for a project."

  use Atlas.MCP.Tool,
    name: "rotate_project_error_dsn",
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
      "Invalidate the current Sentry-compatible Data Source Name for a project and return the freshly minted replacement."

  def execute(conn, %{"project_id" => project_id}) do
    user = Tool.current_user(conn)

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, key} <- Errors.rotate_project_key(project) do
      {:ok, %{"key" => EngineeringSerializers.project_key(key)}}
    else
      {:error, :not_found} -> {:error, "Project not found."}
      {:error, _} -> {:error, "DSN rotation failed."}
    end
  end
end
