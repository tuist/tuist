defmodule AtlasWeb.AutomationControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [execute_tool: 3, mcp_conn: 1]

  alias Atlas.Automations
  alias Atlas.Automations.Executor
  alias Atlas.MCP.Tools.DeleteAutomationBehavior
  alias Atlas.MCP.Tools.GetAutomationRecord
  alias Atlas.MCP.Tools.UpdateAutomationBehavior

  setup %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    %{actor: actor, token: oauth_access_token_fixture(actor)}
  end

  test "API and MCP share behavior CRUD and hide all webhook hashes", %{actor: actor, token: token} do
    created = request(token, :post, "/behaviors", %{"name" => "Value", "type" => "core.value"}) |> json_response(201)
    id = created["data"]["id"]
    allowed = request(token, :put, "/behaviors/#{id}", %{})
    assert json_response(allowed, 405)
    assert get_resp_header(allowed, "allow") == ["GET, PATCH, DELETE"]

    assert {:ok, %{data: %{id: ^id}}} =
             execute_tool(GetAutomationRecord, mcp_conn(actor), %{"kind" => "behaviors", "id" => id})

    assert {:ok, %{data: %{name: "Updated"}}} =
             execute_tool(UpdateAutomationBehavior, mcp_conn(actor), %{"id" => id, "name" => "Updated"})

    assert request(token, :get, "/behaviors/#{id}") |> json_response(200) |> get_in(["data", "name"]) == "Updated"
    assert {:ok, %{data: %{deleted: true}}} = execute_tool(DeleteAutomationBehavior, mcp_conn(actor), %{"id" => id})
    assert request(token, :get, "/behaviors/#{id}") |> json_response(404)
    {workflow, _} = workflow_fixture(actor)
    hook = request(token, :post, "/webhooks", %{"workflow_id" => workflow.id, "name" => "Hook"}) |> json_response(201)
    hook_id = hook["data"]["trigger"]["id"]
    secret = hook["data"]["secret"]
    assert is_binary(secret)
    read = request(token, :get, "/webhooks/#{hook_id}") |> json_response(200)
    refute JSON.encode!(read) =~ secret
    refute JSON.encode!(read) =~ "token_hash"
    assert request(token, :get, "/schedules/#{hook_id}") |> json_response(404)
    assert request(token, :delete, "/schedules/#{hook_id}") |> json_response(404)
    rotated = request(token, :post, "/webhooks/#{hook_id}/rotate-credential") |> json_response(200)
    refute rotated["data"]["secret"] == secret
    assert request(token, :delete, "/webhooks/#{hook_id}") |> json_response(200)
  end

  test "draft CRUD, publication and immutable revision reads", %{token: token} do
    source = JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})
    draft = request(token, :post, "/workflows", %{"name" => "Draft", "source" => source}) |> json_response(201)
    id = draft["data"]["id"]

    assert request(token, :patch, "/workflows/#{id}", %{"name" => "Edited"})
           |> json_response(200)
           |> get_in(["data", "name"]) == "Edited"

    assert request(token, :post, "/workflows", %{"id" => id, "name" => "Wrong", "source" => source})
           |> json_response(422)

    revision = request(token, :post, "/workflows/#{id}/publish") |> json_response(201)
    revision_id = revision["data"]["id"]
    assert request(token, :get, "/revisions/#{revision_id}") |> json_response(200) |> get_in(["data", "number"]) == 1

    assert request(token, :get, "/workflows/#{id}/revisions?page=1")
           |> json_response(200)
           |> get_in(["data", "total_count"]) == 1

    assert request(token, :delete, "/workflows/#{id}") |> json_response(409)
    assert request(token, :delete, "/revisions/#{revision_id}") |> json_response(405)
    assert request(token, :patch, "/revisions/#{revision_id}", %{"source" => source}) |> json_response(405)
  end

  test "every primitive has authorized list/detail reads and lifecycle-managed evidence cannot be overwritten", %{
    actor: actor,
    token: token
  } do
    {workflow, revision} =
      workflow_fixture(actor, [
        %{"id" => "review", "type" => "approval", "reviewer_id" => actor.id, "inputs" => %{"exact" => true}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    {:ok, {[approval], _}} = Automations.list_approvals(actor)
    {:ok, execution} = Automations.get_run(actor, run.id)
    {:ok, {[event | _], _}} = Automations.execution_events(actor, run.id)
    attempt = hd(execution.attempts)

    for {kind, id} <- [
          {"types", "core.value"},
          {"workflows", workflow.id},
          {"revisions", revision.id},
          {"executions", run.id},
          {"attempts", attempt.id},
          {"events", event.id},
          {"approvals", approval.id}
        ] do
      query =
        case kind do
          "revisions" -> "?workflow_id=#{workflow.id}"
          k when k in ["attempts", "events"] -> "?run_id=#{run.id}"
          _ -> ""
        end

      assert request(token, :get, "/#{kind}" <> query) |> json_response(200)
      assert request(token, :get, "/#{kind}/#{id}") |> json_response(200)
      assert {:ok, _} = execute_tool(GetAutomationRecord, mcp_conn(actor), %{"kind" => kind, "id" => id})
    end

    assert request(token, :post, "/attempts", %{}) |> json_response(405)
    assert request(token, :delete, "/events/#{event.id}") |> json_response(405)
    assert request(token, :patch, "/approvals/#{approval.id}", %{"payload" => %{}}) |> json_response(405)

    assert request(token, :post, "/approvals/#{approval.id}/decision", %{"decision" => "approved"})
           |> json_response(200)
  end

  test "API requires a bearer and current scope; malformed arguments are safe", %{conn: conn, token: token} do
    assert build_conn() |> get("/api/automation/types") |> json_response(401)
    {_, reader} = log_in_user(conn, %{scopes: ["automation:read"]})
    read_token = oauth_access_token_fixture(reader)
    assert request(read_token, :get, "/types") |> json_response(200)
    assert request(read_token, :post, "/behaviors", %{"name" => "No", "type" => "core.value"}) |> json_response(403)
    assert request(token, :get, "/workflows?page[bad]=1") |> json_response(422)
    assert request(token, :get, "/behaviors/not-a-uuid") |> json_response(404)

    assert request(token, :post, "/behaviors", %{
             "name" => "No",
             "type" => "core.value",
             "created_by_id" => Ecto.UUID.generate()
           })
           |> json_response(422)

    response = request(token, :get, "/types")
    assert get_resp_header(response, "cache-control") == ["no-store"]
    catalog = json_response(response, 200)["data"]

    assert Enum.all?(
             catalog["operations"],
             &(String.starts_with?(&1["path"], "/api/automation/") && is_map(&1["input_schema"]))
           )
  end

  defp request(token, method, path, body \\ %{}) do
    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    dispatch(conn, @endpoint, method, "/api/automation" <> path, body)
  end
end
