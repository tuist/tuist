defmodule Tuist.OnceEvents.ActionHistoryTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.ActionHistory
  alias Tuist.OnceEvents.Run
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    %{project: project}
  end

  test "bounded identity is project and capability scoped without concatenation collisions" do
    first = ActionHistory.fields(1, %{namespace: "future.v7", key: "a:b"})
    assert first == ActionHistory.fields(1, %{"namespace" => "future.v7", "key" => "a:b"})
    refute first.history_id == ActionHistory.fields(2, %{namespace: "future.v7", key: "a:b"}).history_id
    refute first.history_id == ActionHistory.fields(1, %{namespace: "future.v7", key: "a:b"}, "test").history_id

    refute ActionHistory.fields(1, %{namespace: "a", key: "b:c"}).history_id ==
             ActionHistory.fields(1, %{namespace: "a.b", key: "c"}).history_id

    for invalid <- [
          nil,
          %{},
          %{namespace: "bad namespace", key: "key"},
          %{namespace: "valid", key: String.duplicate("x", 129)},
          %{namespace: "valid", key: "control\n"}
        ] do
      assert ActionHistory.fields(1, invalid).history_id == nil
    end
  end

  test "history survives renamed labels, reordered indices, changed cache keys and versions", %{project: project} do
    now = DateTime.utc_now()

    first =
      occurrence(project, DateTime.add(now, -2, :day), %{
        display_name: "Old name",
        action_index: 4,
        cache_key: "old",
        presentation: %{package: %{ecosystem: "cargo", name: "serde", version: "1.0.200"}}
      })

    second =
      occurrence(project, DateTime.add(now, -1, :day), %{
        display_name: "New name",
        action_index: 8,
        cache_key: "new",
        presentation: %{package: %{ecosystem: "cargo", name: "serde", version: "1.0.228"}}
      })

    assert first.history_id == second.history_id
    {rows, meta} = ActionHistory.list_occurrences(second)
    assert Enum.map(rows, & &1.id) == [second.id, first.id]
    assert meta.total_count == 2
    assert ActionHistory.get_occurrence(project.id, first.run_id, second.id) == {:error, :not_found}
    assert ActionHistory.get_occurrence(project.id, first.run_id, "not-a-uuid") == {:error, :not_found}
  end

  test "statistics exclude restored execution durations and unavailable cache observations", %{project: project} do
    now = DateTime.utc_now()
    first = occurrence(project, DateTime.add(now, -3, :day), %{duration_ms: 100, cache_key: "a"})
    failed = occurrence(project, DateTime.add(now, -2, :day), %{duration_ms: 300, result: "failed", cache_key: "b"})
    restored = occurrence(project, DateTime.add(now, -1, :day), %{duration_ms: 1, was_cached: true, cache_key: "c"})
    _unknown = occurrence(project, DateTime.add(now, -100, :second), %{duration_ms: 200, cache_key: ""})
    stats = ActionHistory.analytics(restored)
    assert stats.total == 4
    assert stats.executions == 3
    assert stats.failures == 1
    assert stats.hits == 1
    assert stats.cache_observations == 3
    assert Decimal.equal?(stats.duration, 200)
    assert stats.first_seen == first.started_at
    assert stats.first_failure == failed.started_at
  end

  test "duplicate completion is idempotent and cannot overwrite the history key", %{project: project} do
    action = occurrence(project, DateTime.utc_now())
    run = Repo.get!(Run, action.once_run_id)

    assert {:ok, nil} =
             OnceEvents.ingest_action(run, %{
               target_execution_id: action.target_execution_id,
               capability: "build",
               action_index: action.action_index,
               result: "succeeded",
               finished_at: action.finished_at,
               history: %{namespace: "different.v1", key: "different"}
             })

    assert Repo.get!(Action, action.id).history_id == action.history_id
  end

  test "colliding keys remain recorded but all occurrences in the run lose authoritative history", %{project: project} do
    action = occurrence(project, DateTime.utc_now())
    run = Repo.get!(Run, action.once_run_id)

    for index <- 1..2 do
      assert {:ok, %{history_ambiguous: true}} =
               OnceEvents.ingest_action(run, %{
                 target_execution_id: "another-target",
                 capability: "build",
                 action_index: index,
                 started_at: action.started_at,
                 finished_at: action.finished_at,
                 result: "succeeded",
                 history: %{namespace: "test.v1", key: "stable-compile"}
               })
    end

    refute ActionHistory.available?(Repo.get!(Action, action.id))
    {[], meta} = ActionHistory.list_occurrences(Repo.get!(Action, action.id))
    assert meta.total_count == 0
  end

  test "foreign project data stays invisible even if its stored UUID matches", %{project: project} do
    action = occurrence(project, DateTime.utc_now())
    other = ProjectsFixtures.project_fixture(build_system: :once)
    foreign = occurrence(other, DateTime.utc_now())
    foreign |> Ecto.Changeset.change(history_id: action.history_id) |> Repo.update!()
    {rows, _meta} = ActionHistory.list_occurrences(action)
    assert Enum.map(rows, & &1.id) == [action.id]
    assert ActionHistory.get_occurrence(project.id, foreign.run_id, foreign.id) == {:error, :not_found}
  end

  test "history is bounded and branch filters apply before pagination and aggregation", %{project: project} do
    now = DateTime.utc_now()
    current = occurrence(project, DateTime.add(now, -2, :day), %{branch: "main"})
    _other = occurrence(project, DateTime.add(now, -1, :day), %{branch: "feature"})
    _old = occurrence(project, DateTime.add(now, -100, :day), %{branch: "main"})
    {rows, meta} = ActionHistory.list_occurrences(current, branch: "main", page_size: 1)
    assert Enum.map(rows, & &1.id) == [current.id]
    assert meta.total_count == 1
    stats = ActionHistory.analytics(current, branch: "main")
    assert stats.total == 1
    assert length(stats.series) <= 40
    assert DateTime.diff(current.started_at, stats.first_seen, :day) == 98
  end

  defp occurrence(project, started_at, attrs \\ %{}) do
    {branch, attrs} = Map.pop(attrs, :branch, "main")

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        git_branch: branch,
        started_at: started_at
      })

    defaults = %{
      target_execution_id: "target",
      capability: "build",
      action_index: 0,
      identifier: "compile",
      display_name: "Compile",
      source_files: [],
      result: "succeeded",
      was_cached: false,
      duration_ms: 100,
      started_at: started_at,
      finished_at: DateTime.add(started_at, 100, :millisecond),
      history: %{namespace: "test.v1", key: "stable-compile"}
    }

    {:ok, action} = OnceEvents.ingest_action(run, Map.merge(defaults, attrs))
    action
  end
end
