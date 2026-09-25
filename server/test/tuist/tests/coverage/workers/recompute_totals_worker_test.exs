defmodule Tuist.Tests.Coverage.Workers.RecomputeTotalsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Workers.RecomputeTotalsWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: project}
  end

  test "republishes one batch of runs and enqueues the next", %{project: project, account: account} do
    files = [CoverageFixtures.file("Sources/A.swift", [1, 1]), CoverageFixtures.file("Sources/API/Client.swift", [0, 0])]
    runs = for _ <- 1..3, do: CoverageFixtures.run_with_coverage(project, account, files)
    run_ids = Enum.map(runs, & &1.id)

    assert project.id |> CoverageFixtures.published_totals(run_ids) |> Map.values() |> Enum.map(& &1.executable_lines) ==
             [4, 4, 4]

    {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/API/**"]})
    stub(Environment, :coverage_recompute_batch_size, fn -> 2 end)

    assert :ok = perform_job(RecomputeTotalsWorker, %{project_id: project.id})
    [next] = all_enqueued(worker: RecomputeTotalsWorker)
    assert is_binary(next.args["after"])

    assert :ok = perform_job(RecomputeTotalsWorker, next.args)
    assert all_enqueued(worker: RecomputeTotalsWorker) == [next]

    assert project.id |> CoverageFixtures.published_totals(run_ids) |> Map.values() |> Enum.map(& &1.executable_lines) ==
             [2, 2, 2]
  end

  test "does nothing for a project that no longer exists" do
    assert :ok = perform_job(RecomputeTotalsWorker, %{project_id: -1})
  end
end
