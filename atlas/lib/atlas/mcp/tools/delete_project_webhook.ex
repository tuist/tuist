defmodule Atlas.MCP.Tools.DeleteProjectWebhook do
  @moduledoc "Deletes a project webhook."

  use Atlas.MCP.Tool,
    name: "delete_project_webhook",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "webhook_id"],
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "webhook_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{"type" => "object"},
        "deleted_webhook" => %{"type" => "object"}
      },
      "required" => ["project", "deleted_webhook"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Webhooks
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Delete a project webhook."

  def execute(conn, %{"project_id" => project_id, "webhook_id" => webhook_id}) do
    user = Tool.current_user(conn)

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         webhook when not is_nil(webhook) <- find_webhook(project, webhook_id),
         {:ok, deleted} <- Webhooks.delete(webhook) do
      {:ok,
       %{
         "project" => EngineeringSerializers.project(Projects.get_project!(project.id)),
         "deleted_webhook" => EngineeringSerializers.webhook(deleted)
       }}
    else
      nil -> {:error, "Webhook not found."}
      {:error, :not_found} -> {:error, "Project not found."}
      {:error, changeset} -> {:error, "Could not delete webhook: #{Tool.format_changeset_errors(changeset)}"}
    end
  end

  defp find_webhook(project, webhook_id) do
    project
    |> Webhooks.list_for_project()
    |> Enum.find(&(&1.id == webhook_id))
  end
end
