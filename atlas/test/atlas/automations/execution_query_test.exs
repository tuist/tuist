defmodule Atlas.Automations.ExecutionQueryTest do
  use Atlas.DataCase, async: true

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.Automations
  alias Atlas.Automations.Run

  setup do
    actor = insert_user!(%{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    %{actor: actor, workflow: workflow, revision: revision}
  end

  test "searches only workflow names and execution IDs, not private inputs or outputs", %{
    actor: actor,
    workflow: workflow,
    revision: revision
  } do
    run =
      run(actor, revision, %{
        input: %{"private" => "do-not-search-payload"},
        outputs: %{"secret" => "do-not-search-output"}
      })

    for query <- [workflow.name, run.id, String.slice(run.id, -12, 12)] do
      assert {:ok, {[found], _}} = Automations.list_runs(actor, %{"q" => query})
      assert found.id == run.id
    end

    for query <- ["do-not-search-payload", "do-not-search-output", "%", "_"] do
      assert {:ok, {[], _}} = Automations.list_runs(actor, %{"q" => query})
    end
  end

  test "filters and orders the complete SQL cohort before the 20-row page", %{actor: actor, revision: revision} do
    now = DateTime.utc_now(:second)
    failed = for i <- 1..25, do: run(actor, revision, %{status: "failed", inserted_at: DateTime.add(now, i)})
    for _ <- 1..5, do: run(actor, revision, %{status: "succeeded", trigger: "webhook"})
    params = %{"status" => "failed", "sort_by" => "created", "sort_order" => "asc"}
    assert {:ok, {page, meta}} = Automations.list_runs(actor, params)
    assert Enum.map(page, & &1.id) == Enum.map(Enum.take(failed, 20), & &1.id)
    assert meta.total_count == 25
    assert {:ok, {page, _}} = Automations.list_runs(actor, Map.put(params, "page", "2"))
    assert Enum.map(page, & &1.id) == Enum.map(Enum.drop(failed, 20), & &1.id)

    assert {:ok, {page, meta}} =
             Automations.list_runs(actor, %{"status" => "failed", "status_op" => "!=", "trigger" => "webhook"})

    assert length(page) == 5
    assert meta.total_count == 5
  end

  test "supports stable workflow/status/trigger sorting and bounded invalid arguments", %{
    actor: actor,
    revision: revision
  } do
    a = run(actor, revision, %{status: "queued", trigger: "schedule"})
    b = run(actor, revision, %{status: "failed", trigger: "manual"})

    for field <- ~w(workflow status trigger created) do
      assert {:ok, {asc, _}} = Automations.list_runs(actor, %{"sort_by" => field, "sort_order" => "asc"})
      assert {:ok, {desc, _}} = Automations.list_runs(actor, %{"sort_by" => field, "sort_order" => "desc"})
      assert Enum.map(asc, & &1.id) == Enum.reverse(Enum.map(desc, & &1.id))
    end

    assert {:ok, {rows, _}} =
             Automations.list_runs(actor, %{
               "sort_by" => "input",
               "sort_order" => "DROP TABLE",
               "status" => "unknown",
               "q" => %{}
             })

    assert MapSet.new(Enum.map(rows, & &1.id)) == MapSet.new([a.id, b.id])
  end

  defp run(actor, revision, attrs) do
    %Run{
      revision_id: revision.id,
      initiated_by_id: actor.id,
      input: %{},
      outputs: %{},
      status: "queued",
      trigger: "manual"
    }
    |> struct(attrs)
    |> Repo.insert!()
  end
end
