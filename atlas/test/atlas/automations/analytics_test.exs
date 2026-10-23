defmodule Atlas.Automations.AnalyticsTest do
  use Atlas.DataCase, async: true

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.Automations
  alias Atlas.Automations.Analytics
  alias Atlas.Automations.Run
  alias Atlas.Repo

  setup do
    actor = insert_user!(%{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    until = Date.add(Date.utc_today(), -2)
    %{actor: actor, workflow: workflow, revision: revision, until: until}
  end

  test "aggregates all revisions, weighted durations, outcomes and comparison cohorts", context do
    %{actor: actor, workflow: workflow, revision: revision, until: until} = context
    {:ok, second} = Automations.publish_workflow(actor, workflow.id)
    {_other, other_revision} = workflow_fixture(actor)
    first = Date.add(until, -6)
    insert_run(actor, revision, "succeeded", first, 10)
    insert_run(actor, revision, "failed", first, 30)
    insert_run(actor, revision, "waiting_approval", first)
    insert_run(actor, second, "succeeded", until, 100)
    insert_run(actor, second, "succeeded", until, 50)
    insert_run(actor, second, "rejected", until, 20)
    insert_run(actor, second, "cancelled", until)
    insert_run(actor, second, "failed", until, -5)
    insert_run(actor, second, "queued", until)
    insert_run(actor, second, "running", until)
    insert_run(actor, other_revision, "succeeded", until, 2)
    insert_run(actor, revision, "succeeded", Date.add(first, -1), 200)
    insert_run(actor, revision, "succeeded", Date.add(first, -8), 500)
    insert_run(actor, revision, "succeeded", Date.add(until, 1), 500)

    params = %{"workflow_id" => workflow.id, "days" => 7, "end_date" => Date.to_iso8601(until)}
    assert {:ok, result} = Analytics.get(actor, params)
    assert result.total.executions == 10
    assert result.total.finished == 7
    assert result.total.succeeded == 3
    assert result.total.active == 3
    assert result.total.waiting_approval == 1
    assert result.total.duration_samples == 5
    assert_in_delta result.total.average_completion_seconds, 42.0, 0.001
    assert_in_delta result.total.success_rate, 300 / 7, 0.001
    assert result.previous.executions == 1
    assert result.previous.average_completion_seconds == 200.0
    assert result.timezone == "UTC"
    assert length(result.points) == 7
    assert Enum.at(result.points, 1).executions == 0
    assert is_nil(Enum.at(result.points, 1).success_rate)
    assert is_nil(Enum.at(result.points, 1).average_completion_seconds)
    assert {:ok, {runs, meta}} = Automations.list_runs(actor, params)
    assert meta.total_count == 10
    assert length(runs) == 10
    assert {:ok, {_, unfiltered}} = Automations.list_runs(actor, %{"workflow_id" => workflow.id})
    assert unfiltered.total_count == 13
  end

  test "retains measured zeros while unfinished or empty cohorts remain unavailable", context do
    %{actor: actor, revision: revision, until: until} = context
    params = %{"days" => 7, "end_date" => Date.to_iso8601(until)}
    assert {:ok, empty} = Analytics.get(actor, params)
    assert empty.total.executions == 0
    assert is_nil(empty.total.success_rate)
    assert is_nil(empty.total.average_completion_seconds)
    assert Enum.all?(empty.points, &(&1.executions == 0))
    insert_run(actor, revision, "queued", until)
    assert {:ok, pending} = Analytics.get(actor, params)
    assert pending.total.executions == 1
    assert is_nil(pending.total.success_rate)
    assert is_nil(pending.total.average_completion_seconds)
    insert_run(actor, revision, "failed", until, 0)
    assert {:ok, measured} = Analytics.get(actor, params)
    assert measured.total.success_rate == 0.0
    assert measured.total.average_completion_seconds == 0.0
    assert measured.total.duration_samples == 1
  end

  test "uses UTC midnight boundaries independently of the database session timezone", context do
    %{actor: actor, revision: revision, until: until} = context
    Repo.query!("SET LOCAL TIME ZONE 'America/Los_Angeles'")
    midnight = DateTime.new!(until, ~T[00:00:00], "Etc/UTC")
    insert_at(actor, revision, "succeeded", midnight, 0)
    insert_at(actor, revision, "succeeded", DateTime.add(midnight, -1), 0)
    insert_at(actor, revision, "succeeded", DateTime.add(midnight, 86_399), 0)
    insert_at(actor, revision, "succeeded", DateTime.add(midnight, 86_400), 0)
    assert {:ok, result} = Analytics.get(actor, %{"days" => 1, "end_date" => Date.to_iso8601(until)})
    assert result.total.executions == 2
    assert result.previous.executions == 1
    assert [%{date: date, executions: 2}] = result.points
    assert date == Date.to_iso8601(until)
  end

  test "validates bounded periods and workflow identities and enforces read access", %{actor: actor} do
    reader = insert_user!(%{scopes: ["automation:read"]})
    stranger = insert_user!(%{})
    assert {:ok, _} = Analytics.get(reader)
    assert {:error, :forbidden} = Analytics.get(stranger)

    for days <- [0, 91, -1, "7garbage", true, false, nil] do
      assert {:error, :invalid_period} = Analytics.get(actor, %{"days" => days})
      assert {:error, :invalid_period} = Automations.list_runs(actor, %{"days" => days})
    end

    assert {:error, :invalid_period} = Analytics.get(actor, %{"end_date" => "invalid"})
    assert {:error, :invalid_period} = Analytics.get(actor, %{"end_date" => "-9999-01-01"})

    assert {:error, :invalid_period} =
             Analytics.get(actor, %{"end_date" => Date.to_iso8601(Date.add(Date.utc_today(), 1))})

    assert {:error, :not_found} = Analytics.get(actor, %{"workflow_id" => Ecto.UUID.generate()})
    assert {:error, :not_found} = Analytics.get(actor, %{"workflow_id" => "invalid"})
  end

  defp insert_run(actor, revision, status, date, seconds \\ nil) do
    insert_at(actor, revision, status, DateTime.new!(date, ~T[12:00:00], "Etc/UTC"), seconds)
  end

  defp insert_at(actor, revision, status, started_at, seconds) do
    Repo.insert!(%Run{
      revision_id: revision.id,
      initiated_by_id: actor.id,
      status: status,
      trigger: "manual",
      inserted_at: started_at,
      updated_at: started_at,
      completed_at: if(!is_nil(seconds), do: DateTime.add(started_at, seconds))
    })
  end
end
