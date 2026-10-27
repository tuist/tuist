defmodule Atlas.Automations.NativeTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AutomationsFixtures

  alias Atlas.Automations
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Native
  alias Atlas.Automations.Run
  alias Atlas.Repo

  test "admission is idempotent, revision-bound, and safe after publication changes", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    key = Ecto.UUID.generate()
    assert {:ok, first} = Native.run(actor, workflow.id, revision.id, key, %{"private" => "input"})
    id = first.id
    assert {:ok, %{id: ^id}} = Native.run(actor, workflow.id, revision.id, key, %{"private" => "input"})

    assert {:ok, %{id: ^id}} =
             Native.run(actor, String.upcase(workflow.id), String.upcase(revision.id), String.upcase(key), %{
               "private" => "input"
             })

    assert {:error, :idempotency_conflict} = Native.run(actor, workflow.id, revision.id, key, %{})
    {:ok, _} = Automations.publish_workflow(actor, workflow.id)
    assert {:ok, %{id: ^id}} = Native.run(actor, workflow.id, revision.id, key, %{"private" => "input"})
    assert {:error, :revision_changed} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    assert Repo.aggregate(Run, :count) == 1
    refute Map.has_key?(first, :input)
    refute Map.has_key?(first, :outputs)
    assert [%{step_id: "value", status: "pending"}] = first.steps
  end

  test "snapshot follows committed progress without copying payloads or source", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    {:ok, run} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    assert {:ok, :ok} = Executor.advance(run.id)
    assert {:ok, snapshot} = Native.execution(actor, run.id)
    assert snapshot.sequence > run.sequence
    assert [%{step_id: "value", status: "succeeded"}] = snapshot.steps
    encoded = JSON.encode!(snapshot)
    refute encoded =~ "Hello"
    refute encoded =~ "source"
    refute encoded =~ "diagnostic"
    assert {:ok, %{outputs_json: outputs}} = Native.result(actor, run.id)
    assert JSON.decode!(outputs) == %{"value" => %{"message" => "Hello"}}
  end

  test "only the assigned reviewer sees and decides the exact native approval", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {_, other} = log_in_user(build_conn(), %{scopes: ["automation:write"]})

    {workflow, revision} =
      workflow_fixture(actor, [
        %{"id" => "review", "type" => "approval", "reviewer_id" => actor.id, "inputs" => %{"value" => "Exact"}}
      ])

    {:ok, run} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    assert {:ok, :ok} = Executor.advance(run.id)
    {:ok, %{items: [summary]}} = Native.approvals(actor, %{})
    {:ok, approval} = Native.approval(actor, summary.id)
    assert JSON.decode!(approval.payload_json) == %{"value" => "Exact"}
    assert {:ok, %{items: []}} = Native.approvals(other, %{})
    assert {:error, :not_found} = Native.approval(other, summary.id)
    assert {:error, :payload_changed} = Native.decide(actor, summary.id, "approved", "wrong")
    assert {:ok, snapshot} = Native.decide(actor, summary.id, "approved", approval.payload_digest)
    assert snapshot.status == "queued"
    assert {:error, :decision_not_allowed} = Native.decide(actor, summary.id, "approved", approval.payload_digest)
  end

  test "approval display preserves integers beyond native JSON numeric precision", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    integer = 100_000_000_000_000_000_001

    {workflow, revision} =
      workflow_fixture(actor, [
        %{"id" => "review", "type" => "approval", "reviewer_id" => actor.id, "inputs" => %{"integer" => integer}}
      ])

    {:ok, run} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    Executor.advance(run.id)
    {:ok, %{items: [summary]}} = Native.approvals(actor, %{})
    {:ok, approval} = Native.approval(actor, summary.id)
    assert approval.payload_json =~ Integer.to_string(integer)
    refute Map.has_key?(approval, :payload)
  end

  test "HTTP authenticates and rejects readers, malformed identities and changed inputs", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    token = oauth_access_token_fixture(actor)

    request = fn path, body ->
      build_conn() |> put_req_header("authorization", "Bearer #{token}") |> post(path, body)
    end

    path = "/api/native/automation/workflows/#{workflow.id}/run"
    body = %{"revision_id" => revision.id, "request_id" => Ecto.UUID.generate(), "input" => %{}}
    first = request.(path, body) |> json_response(200)
    assert request.(path, body) |> json_response(200) |> Access.get("id") == first["id"]
    assert build_conn() |> get("/api/native/automation/workflows") |> json_response(401)
    assert request.("/api/native/automation/executions/not-a-uuid/control", %{"command" => 123}) |> json_response(422)
    {_, reader} = log_in_user(build_conn(), %{scopes: ["automation:read"]})
    reader_token = oauth_access_token_fixture(reader)

    assert build_conn()
           |> put_req_header("authorization", "Bearer #{reader_token}")
           |> post(path, body)
           |> json_response(403)

    assert {:ok, %{items: []}} = Native.executions(reader, %{})
    assert {:ok, %{can_run: false}} = Native.workflow(reader, workflow.id)
    assert {:ok, %{items: [_]}} = Native.workflows(reader, %{"page" => %{}})
    assert {:ok, %{items: []}} = Native.executions(reader, %{"page" => []})
  end
end
