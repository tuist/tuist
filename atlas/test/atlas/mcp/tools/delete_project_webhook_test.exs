defmodule Atlas.MCP.Tools.DeleteProjectWebhookTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Webhooks
  alias Atlas.MCP.Tools.DeleteProjectWebhook

  test "deletes a webhook" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, {webhook, _}} = Webhooks.create(project, %{"name" => "G", "source" => "grafana"})
    user = insert_user!()

    {:ok, %{"deleted_webhook" => payload}} =
      execute_tool(DeleteProjectWebhook, mcp_conn(user), %{
        "project_id" => project.id,
        "webhook_id" => webhook.id
      })

    assert payload["id"] == webhook.id
    assert Webhooks.list_for_project(project) == []
  end

  test "returns an error when the webhook does not exist" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    assert {:error, "Webhook not found."} =
             execute_tool(DeleteProjectWebhook, mcp_conn(user), %{
               "project_id" => project.id,
               "webhook_id" => "00000000-0000-0000-0000-000000000000"
             })
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(DeleteProjectWebhook, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "webhook_id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
