defmodule AtlasWeb.AutomationWebhookControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AutomationsFixtures

  alias Atlas.Automations

  test "requires a credential and delivery ID and admits JSON exactly once", %{conn: conn} do
    {_conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)

    {:ok, %{trigger: hook, secret: secret}} =
      Automations.create_trigger(actor, workflow.id, %{"name" => "Hook", "kind" => "webhook"})

    path = ~p"/api/automation/hooks/#{hook.id}"
    assert build_conn() |> post(path, %{}) |> json_response(401)

    request = fn ->
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> put_req_header("x-delivery-id", "delivery-1")
      |> post(path, %{"id" => "body-id", "title" => "Payload"})
    end

    first = request.() |> json_response(202)
    assert request.() |> json_response(202) == first
    {:ok, run} = Automations.get_run(actor, first["execution_id"])
    assert run.input == %{"id" => "body-id", "title" => "Payload"}
    assert {:ok, _} = Automations.set_trigger_enabled(actor, hook.id, false)
    assert request.() |> json_response(401)
  end
end
