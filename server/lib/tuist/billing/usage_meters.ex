defmodule Tuist.Billing.UsageMeters do
  @moduledoc """
  Measures the cache downloads and test case runs that usage-based pricing
  bills an account for, over half-open windows `[period_start, period_end)`.

  Usage is attributed to the account that owns the project. Kura events carry
  that account as their tenant, and project-scoped tables are mapped to it
  through `projects.account_id`, because their own `account_id` is the uploader.
  """
  import Ecto.Query

  alias Tuist.Cache.CASEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.Kura.Regions
  alias Tuist.Kura.UsageEvent
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runners.Job
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRunByProject
  alias Tuist.Tests.TestCaseRunByTestRun

  @project_ids_chunk_size 5_000
  @cache_artifact_kinds ~w(module xcode gradle reapi nx metro)
  @runner_job_lookback_days 7

  @doc """
  Cache downloads per UTC day, split by project and by whether they were served
  from a Tuist Runners cache region.

  Returns `%{date, project_id, runners, bytes, requests}` rows. `project_id` is
  `0` for Kura traffic that did not resolve to a project. Kura artifact kinds
  other than the module, Xcode, Gradle, Bazel, Nx, and Metro caches are not
  counted.
  """
  def cache_downloads(account_id, %DateTime{} = period_start, %DateTime{} = period_end) when is_integer(account_id) do
    kura_downloads(account_id, period_start, period_end) ++
      compilation_cache_downloads(account_id, period_start, period_end)
  end

  defp kura_downloads(account_id, period_start, period_end) do
    runner_regions = runner_region_ids()

    deduped =
      from(e in UsageEvent,
        where: e.account_id == ^account_id and e.direction == "egress",
        where: e.window_start >= ^to_naive(period_start) and e.window_start < ^to_naive(period_end),
        group_by: e.event_id,
        select: %{
          project_id: fragment("argMax(?, ?)", e.project_id, e.inserted_at),
          artifact_kind: fragment("argMax(?, ?)", e.artifact_kind, e.inserted_at),
          region: fragment("argMax(?, ?)", e.region, e.inserted_at),
          window_start: fragment("argMax(?, ?)", e.window_start, e.inserted_at),
          bytes: fragment("argMax(?, ?)", e.bytes, e.inserted_at),
          request_count: fragment("argMax(?, ?)", e.request_count, e.inserted_at)
        }
      )

    from(e in subquery(deduped),
      where: e.artifact_kind in ^@cache_artifact_kinds,
      group_by: [fragment("toDate(?)", e.window_start), e.project_id, e.region],
      select: %{
        date: fragment("toDate(?)", e.window_start),
        project_id: e.project_id,
        region: e.region,
        bytes: fragment("sum(?)", e.bytes),
        requests: fragment("sum(?)", e.request_count)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        date: row.date,
        project_id: row.project_id,
        runners: row.region in runner_regions,
        bytes: to_integer(row.bytes),
        requests: to_integer(row.requests)
      }
    end)
  end

  defp compilation_cache_downloads(account_id, period_start, period_end) do
    account_id
    |> project_ids()
    |> Enum.chunk_every(@project_ids_chunk_size)
    |> Enum.flat_map(fn project_ids ->
      ClickHouseRepo.all(
        from(e in CASEvent,
          where: fragment("? IN (?)", e.project_id, type(^project_ids, {:array, :integer})),
          where: e.action == "download",
          where: e.inserted_at >= ^to_naive(period_start) and e.inserted_at < ^to_naive(period_end),
          group_by: [fragment("toDate(?)", e.inserted_at), e.project_id],
          select: %{
            date: fragment("toDate(?)", e.inserted_at),
            project_id: e.project_id,
            bytes: fragment("sum(?)", e.size),
            requests: fragment("count()")
          }
        )
      )
    end)
    |> Enum.map(fn row ->
      %{
        date: row.date,
        project_id: row.project_id,
        runners: false,
        bytes: to_integer(row.bytes),
        requests: to_integer(row.requests)
      }
    end)
  end

  @doc """
  Test case runs per UTC day of `ran_at`, split by project, by status, and by
  whether their test run came from a Tuist Runners job.

  Returns `%{date, project_id, status, runners, count}` rows, where `status` is
  one of `"success"`, `"failure"`, or `"skipped"`.
  """
  def test_case_runs(account_id, %DateTime{} = period_start, %DateTime{} = period_end) when is_integer(account_id) do
    project_ids = project_ids(account_id)

    all =
      project_ids
      |> Enum.chunk_every(@project_ids_chunk_size)
      |> Enum.flat_map(&all_test_case_runs(&1, period_start, period_end))
      |> counts_by_day_project_and_status()

    on_runners =
      project_ids
      |> Enum.chunk_every(@project_ids_chunk_size)
      |> Enum.flat_map(&runner_test_case_runs(&1, account_id, period_start, period_end))
      |> counts_by_day_project_and_status()

    elsewhere =
      Enum.map(all, fn {key, count} -> {key, max(count - Map.get(on_runners, key, 0), 0)} end)

    [{false, elsewhere}, {true, on_runners}]
    |> Enum.flat_map(fn {runners, counts} ->
      Enum.map(counts, fn {{date, project_id, status}, count} ->
        %{date: date, project_id: project_id, status: status, runners: runners, count: count}
      end)
    end)
    |> Enum.reject(&(&1.count == 0))
  end

  defp all_test_case_runs(project_ids, period_start, period_end) do
    ClickHouseRepo.all(
      from(r in TestCaseRunByProject,
        hints: ["FINAL"],
        where: fragment("? IN (?)", r.project_id, type(^project_ids, {:array, :integer})),
        where: r.ran_at >= ^period_start and r.ran_at < ^period_end,
        group_by: [fragment("toDate(?)", r.ran_at), r.project_id, r.status],
        select: %{
          date: fragment("toDate(?)", r.ran_at),
          project_id: r.project_id,
          status: r.status,
          count: fragment("count()")
        }
      )
    )
  end

  defp runner_test_case_runs(project_ids, account_id, period_start, period_end) do
    workflow_run_ids =
      from(j in Job,
        where: j.account_id == ^account_id and j.workflow_run_id > 0,
        where: j.enqueued_at >= ^DateTime.add(period_start, -@runner_job_lookback_days, :day),
        where: j.enqueued_at < ^period_end,
        select: j.workflow_run_id
      )

    test_run_ids =
      from(t in Test,
        where: fragment("? IN (?)", t.project_id, type(^project_ids, {:array, :integer})),
        where: fragment("toInt64OrZero(?)", t.ci_run_id) in subquery(workflow_run_ids),
        select: t.id
      )

    ClickHouseRepo.all(
      from(r in TestCaseRunByTestRun,
        hints: ["FINAL"],
        where: r.test_run_id in subquery(test_run_ids),
        where: r.ran_at >= ^period_start and r.ran_at < ^period_end,
        group_by: [fragment("toDate(?)", r.ran_at), r.project_id, r.status],
        select: %{
          date: fragment("toDate(?)", r.ran_at),
          project_id: r.project_id,
          status: r.status,
          count: fragment("count()")
        }
      )
    )
  end

  defp counts_by_day_project_and_status(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.update(acc, {row.date, row.project_id, row.status}, to_integer(row.count), &(&1 + to_integer(row.count)))
    end)
  end

  @doc """
  The names of the projects `account_id` owns, keyed by id.
  """
  def project_names(account_id) when is_integer(account_id) do
    Map.new(Repo.all(from(p in Project, where: p.account_id == ^account_id, select: {p.id, p.name})))
  end

  defp project_ids(account_id) do
    Repo.all(from(p in Project, where: p.account_id == ^account_id, select: p.id))
  end

  defp runner_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.private?/1)
    |> Enum.map(& &1.id)
  end

  defp to_naive(%DateTime{} = datetime), do: datetime |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = decimal), do: Decimal.to_integer(decimal)
  defp to_integer(value) when is_integer(value), do: value
end
