defmodule Tuist.HomeActivityTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.HomeActivity
  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "failed test runs are bounded, newest first, and project/time scoped" do
    project = ProjectsFixtures.project_fixture()
    other = ProjectsFixtures.project_fixture()
    now = NaiveDateTime.utc_now()

    runs =
      for offset <- [60, 120, 180, 240] do
        {:ok, run} =
          RunsFixtures.test_fixture(project_id: project.id, status: "failure", ran_at: NaiveDateTime.add(now, -offset))

        run
      end

    for {owner, status, offset} <- [
          {project, "success", -10},
          {project, "failure", -8 * 86_400},
          {project, "failure", 86_400},
          {other, "failure", -5}
        ] do
      RunsFixtures.test_fixture(project_id: owner.id, status: status, ran_at: NaiveDateTime.add(now, offset))
    end

    assert {:ok, results} = HomeActivity.test_failures(project)
    assert Enum.map(results, & &1.id) == runs |> Enum.take(3) |> Enum.map(& &1.id)
    assert Enum.all?(results, &is_integer(&1.occurred_at))
  end

  test "new flaky tests use the current flaky-state transition, not the last run" do
    project = ProjectsFixtures.project_fixture()
    other = ProjectsFixtures.project_fixture()
    now = NaiveDateTime.utc_now()
    newly_marked = test_case(project, "recentlyMarked", NaiveDateTime.add(now, -30 * 86_400))
    event(project, newly_marked, "marked_flaky", NaiveDateTime.add(now, -3600))

    long_flaky = test_case(project, "longFlakyButRanToday", now)
    event(project, long_flaky, "marked_flaky", NaiveDateTime.add(now, -8 * 86_400))

    resolved = test_case(project, "resolved", now)
    event(project, resolved, "marked_flaky", NaiveDateTime.add(now, -7200))
    event(project, resolved, "unmarked_flaky", NaiveDateTime.add(now, -1800))

    remarked = test_case(project, "newFlakyEpisode", now)
    event(project, remarked, "marked_flaky", NaiveDateTime.add(now, -9 * 86_400))
    event(project, remarked, "unmarked_flaky", NaiveDateTime.add(now, -2 * 86_400))
    event(project, remarked, "marked_flaky", NaiveDateTime.add(now, -600))

    foreign = test_case(other, "otherProject", now)
    event(other, foreign, "marked_flaky", NaiveDateTime.add(now, -60))
    future = test_case(project, "futureMark", now)
    event(project, future, "marked_flaky", NaiveDateTime.add(now, 86_400))

    assert {:ok, results} = HomeActivity.flaky_tests(project)
    assert Enum.map(results, & &1.id) == [remarked.id, newly_marked.id]

    assert hd(results).occurred_at ==
             now |> NaiveDateTime.add(-600) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  end

  test "flaky results have a stable three-row bound even when mark timestamps tie" do
    project = ProjectsFixtures.project_fixture()
    time = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)

    for index <- 1..5 do
      test_case = test_case(project, "test#{index}", time)
      event(project, test_case, "marked_flaky", time)
    end

    assert {:ok, first} = HomeActivity.flaky_tests(project)
    assert {:ok, second} = HomeActivity.flaky_tests(project)
    assert length(first) == 3
    assert first == second
  end

  test "unsupported sources are not returned as healthy empty results" do
    assert HomeActivity.build_failures(%{build_system: :cargo}) == {:error, :unsupported}
    assert HomeActivity.build_failures(%{build_system: :mix}) == {:error, :unsupported}
    assert HomeActivity.test_failures(%{build_system: :once}) == {:error, :unsupported}
    assert HomeActivity.flaky_tests(%{build_system: :once}) == {:error, :unsupported}
  end

  defp test_case(project, name, last_ran_at) do
    test_case = RunsFixtures.test_case_fixture(project_id: project.id, name: name, last_ran_at: last_ran_at)
    IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])
    test_case
  end

  defp event(project, test_case, type, time) do
    RunsFixtures.test_case_event_fixture(
      project_id: project.id,
      test_case_id: test_case.id,
      event_type: type,
      inserted_at: time
    )
  end
end
