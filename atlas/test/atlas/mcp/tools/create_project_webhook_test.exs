defmodule Atlas.MCP.Tools.CreateProjectWebhookTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Webhooks
  alias Atlas.MCP.Tools.CreateProjectWebhook

  test "creates a webhook and returns its one-time URL" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"webhook" => webhook, "webhook_url" => url}} =
      execute_tool(CreateProjectWebhook, mcp_conn(user), %{
        "project_id" => project.id,
        "name" => "Grafana prod",
        "source" => "grafana"
      })

    assert webhook["name"] == "Grafana prod"
    assert webhook["source"] == "grafana"
    assert url =~ "/webhooks/projects/#{project.id}/grafana/"
    assert [_stored] = Webhooks.list_for_project(project)
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(CreateProjectWebhook, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "name" => "Grafana",
               "source" => "grafana"
             })
  end
end
