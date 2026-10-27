defmodule Atlas.MCP.AutomationTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Automations
  alias Atlas.Automations.Executor
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.CreateAutomationTrigger
  alias Atlas.MCP.Tools.GetAutomationAnalytics
  alias Atlas.MCP.Tools.GetAutomationExecutionTrace
  alias Atlas.MCP.Tools.GetAutomationWorkflow
  alias Atlas.MCP.Tools.ListAutomationRecords
  alias Atlas.MCP.Tools.ListAutomationTypes
  alias Atlas.MCP.Tools.PublishAutomationWorkflow
  alias Atlas.MCP.Tools.RunAutomationWorkflow
  alias Atlas.MCP.Tools.SaveAutomationWorkflow

  test "MCP can pin a contract and safely replay a launch request" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    conn = mcp_conn(actor)
    {workflow, revision} = Atlas.AutomationsFixtures.workflow_fixture(actor)
    args = %{"id" => workflow.id, "revision_id" => revision.id, "request_id" => Ecto.UUID.generate(), "input" => %{}}
    assert {:ok, %{data: %{id: id}}} = execute_tool(RunAutomationWorkflow, conn, args)
    assert {:ok, %{data: %{id: ^id}}} = execute_tool(RunAutomationWorkflow, conn, args)
    assert {:error, _} = execute_tool(RunAutomationWorkflow, conn, Map.delete(args, "revision_id"))
  end

  test "trace inspection is scoped and excludes execution payloads" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    {workflow, _} = Atlas.AutomationsFixtures.workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{"secret" => "private-input"})
    Executor.advance(run.id)
    reader = mcp_conn(insert_user!(%{scopes: ["automation:read"]}))
    assert {:ok, %{data: trace}} = execute_tool(GetAutomationExecutionTrace, reader, %{"id" => run.id})
    assert trace.execution.trace_id == run.trace_id
    assert trace.spans != [] && trace.events != []
    refute JSON.encode!(trace) =~ "private-input"
    assert {:error, _} = execute_tool(GetAutomationExecutionTrace, mcp_conn(insert_user!(%{})), %{"id" => run.id})
  end

  test "typed MCP authoring, validation, publication, and discovery" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    conn = mcp_conn(actor)
    assert {:ok, %{data: %{types: types}}} = execute_tool(ListAutomationTypes, conn, %{})
    assert Enum.any?(types, &(&1.name == "javascript.evaluate"))
    source = JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})

    assert {:ok, %{data: %{id: id}}} =
             execute_tool(SaveAutomationWorkflow, conn, %{"name" => "MCP workflow", "source" => source})

    assert {:ok, %{data: %{number: 1}}} = execute_tool(PublishAutomationWorkflow, conn, %{"id" => id})
    assert {:ok, %{data: %{items: [%{id: ^id}]}}} = execute_tool(ListAutomationRecords, conn, %{"kind" => "workflows"})
  end

  test "MCP can save ready versions atomically and reject stale edits" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    conn = mcp_conn(actor)
    source = JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})

    assert {:ok, %{data: %{id: id, published_revision: %{id: first_id, number: 1, source: ^source}}}} =
             execute_tool(SaveAutomationWorkflow, conn, %{
               "name" => "Ready workflow",
               "source" => source,
               "publish" => true,
               "expected_revision_id" => nil
             })

    assert {:ok, %{data: %{published_revision: %{number: 2}}}} =
             execute_tool(SaveAutomationWorkflow, conn, %{
               "id" => id,
               "name" => "Second version",
               "source" => source,
               "publish" => true,
               "expected_revision_id" => first_id
             })

    assert {:error, _} =
             execute_tool(SaveAutomationWorkflow, conn, %{
               "id" => id,
               "name" => "Stale",
               "source" => source,
               "publish" => true,
               "expected_revision_id" => first_id
             })

    assert {:ok, %{data: %{name: "Second version", published_revision: %{number: 2, source: ^source}}}} =
             execute_tool(GetAutomationWorkflow, conn, %{"id" => id})
  end

  test "invalid atomic saves do not leave drafts behind" do
    actor = insert_user!(%{scopes: ["automation:write"]})

    assert {:error, _} =
             execute_tool(SaveAutomationWorkflow, mcp_conn(actor), %{
               "name" => "Invalid",
               "source" => "{}",
               "publish" => true
             })

    assert {:ok, {[], _}} = Automations.list_workflows(actor)
  end

  test "readers can inspect bounded execution metrics and scoped execution history" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    reader = insert_user!(%{scopes: ["automation:read"]})
    {workflow, _} = Atlas.AutomationsFixtures.workflow_fixture(actor)
    {:ok, _} = Automations.run_workflow(actor, workflow.id, %{})
    conn = mcp_conn(reader)

    assert {:ok, %{data: %{total: %{executions: 1, success_rate: nil}, points: points}}} =
             execute_tool(GetAutomationAnalytics, conn, %{"workflow_id" => workflow.id, "days" => 7})

    assert length(points) == 7

    assert {:ok, %{data: %{total_count: 1}}} =
             execute_tool(ListAutomationRecords, conn, %{
               "kind" => "executions",
               "workflow_id" => workflow.id,
               "days" => 7
             })

    assert {:error, _} = execute_tool(GetAutomationAnalytics, conn, %{"days" => 91})
    assert {:error, _} = execute_tool(GetAutomationAnalytics, mcp_conn(insert_user!(%{})), %{})
  end

  test "credentials are returned once and excluded from list results" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    conn = mcp_conn(actor)
    {workflow, _} = Atlas.AutomationsFixtures.workflow_fixture(actor)

    assert {:ok, %{data: %{secret: secret}}} =
             execute_tool(CreateAutomationTrigger, conn, %{
               "workflow_id" => workflow.id,
               "name" => "Hook",
               "kind" => "webhook"
             })

    assert {:ok, %{data: data}} = execute_tool(ListAutomationRecords, conn, %{"kind" => "webhooks"})
    refute JSON.encode!(data) =~ secret
    refute JSON.encode!(data) =~ "token_hash"
  end

  test "discovery hides automation from unassigned users and mutations from readers" do
    for {scopes, expected} <- [
          {[], []},
          {["automation:read"],
           [
             "list_automation_types",
             "list_automation_records",
             "get_automation_analytics",
             "get_automation_workflow",
             "get_automation_execution",
             "get_automation_execution_trace",
             "get_automation_record"
           ]}
        ] do
      conn = scopes |> then(&insert_user!(%{scopes: &1})) |> mcp_conn()
      response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1})
      names = response["result"]["tools"] |> Enum.map(& &1["name"]) |> Enum.filter(&String.contains?(&1, "automation"))
      assert Enum.sort(names) == Enum.sort(expected)
    end

    reader = insert_user!(%{scopes: ["automation:read"]})
    assert {:error, _} = execute_tool(SaveAutomationWorkflow, mcp_conn(reader), %{"name" => "Denied", "source" => "{}"})
    assert {:ok, {[], _}} = Automations.list_workflows(reader)
  end
end
