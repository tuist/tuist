defmodule TuistWeb.Webhooks.BazelActionsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel.Action
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Observation
  alias Tuist.ClickHouseRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @key "bazel-actions-test-key"

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    stub(Tuist.Environment, :cache_api_key, fn -> @key end)
    %{project: project}
  end

  test "signed batches index executions, retain native diagnostics and deduplicate replays", %{
    conn: conn,
    project: project
  } do
    FunWithFlags.enable(:build_entities, for_actor: project)
    action = action()
    legacy = Map.drop(action, ["target_label", "mnemonic", "duration_ms"])
    payload = %{"account_handle" => project.account.name, "project_handle" => project.name, "actions" => [action, legacy]}

    for _ <- 1..2 do
      assert conn |> signed_post("/webhooks/bazel-actions/batch", payload) |> json_response(202) == %{}
    end

    Action.Buffer.flush()
    Observation.Buffer.flush()

    assert ClickHouseRepo.exists?(
             from(a in Action, where: a.project_id == ^project.id and a.primary_output == "bazel-out/debug/lib.o")
           )

    {[entity], %{total_count: 1}} = BuildEntities.list(project.id, :bazel, "action")
    assert entity.identity == Map.take(action, ~w(target_label mnemonic primary_output))
    {[observation], %{total_count: 1}} = BuildEntities.history(project.id, :bazel, "action", entity.id)
    assert observation.duration_ms == 0
    assert observation.status == "success"
    assert observation.cache_status == "none"
  end

  test "legacy single reports and disabled inventories keep accepting diagnostics without indexing", %{
    conn: conn,
    project: project
  } do
    payload = Map.merge(action(), %{"account_handle" => project.account.name, "project_handle" => project.name})
    assert conn |> signed_post("/webhooks/bazel-actions", payload) |> json_response(202) == %{}
    Action.Buffer.flush()
    Observation.Buffer.flush()
    assert ClickHouseRepo.exists?(from(a in Action, where: a.project_id == ^project.id))
    refute ClickHouseRepo.exists?(from(o in Observation, where: o.project_id == ^project.id))

    FunWithFlags.enable(:build_entities, for_actor: project)
    legacy = Map.drop(payload, ~w(target_label mnemonic duration_ms))
    assert conn |> signed_post("/webhooks/bazel-actions", legacy) |> json_response(202) == %{}
    Observation.Buffer.flush()
    refute ClickHouseRepo.exists?(from(o in Observation, where: o.project_id == ^project.id))
  end

  defp action do
    %{
      "invocation_id" => "signed-invocation",
      "target_label" => "//app:lib",
      "mnemonic" => "CppCompile",
      "primary_output" => "bazel-out/debug/lib.o",
      "started_at_ms" => System.system_time(:millisecond) - 1000,
      "duration_ms" => 0,
      "success" => true,
      "log" => "compiler output",
      "log_truncated" => false
    }
  end

  defp signed_post(conn, path, payload) do
    body = JSON.encode!(payload)
    signature = :hmac |> :crypto.mac(:sha256, @key, body) |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cache-signature", signature)
    |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
    |> post(path, body)
  end
end
