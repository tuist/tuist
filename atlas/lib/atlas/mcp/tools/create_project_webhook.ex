defmodule Atlas.MCP.Tools.CreateProjectWebhook do
  @moduledoc "Creates a per-project inbound webhook and returns its one-time URL."

  use Atlas.MCP.Tool,
    name: "create_project_webhook",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "name", "source"],
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "source" => %{"type" => "string", "enum" => ["grafana"]}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{"type" => "object"},
        "webhook" => %{"type" => "object"},
        "webhook_url" => %{"type" => "string"}
      },
      "required" => ["project", "webhook", "webhook_url"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Webhooks
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Create a project webhook and return its one-time URL."

  def execute(conn, %{"project_id" => project_id} = args) do
    user = Tool.current_user(conn)
    attrs = Map.take(args, ["name", "source"])

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, {webhook, token}} <- Webhooks.create(project, attrs) do
      {:ok,
       %{
         "project" => EngineeringSerializers.project(Projects.get_project!(project.id)),
         "webhook" => EngineeringSerializers.webhook(webhook),
         "webhook_url" => EngineeringSerializers.webhook_ingest_url(project.id, webhook.source, token)
       }}
    else
      {:error, :not_found} -> {:error, "Project not found."}
      {:error, changeset} -> {:error, "Could not create webhook: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
