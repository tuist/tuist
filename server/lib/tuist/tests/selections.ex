defmodule Tuist.Tests.Selections do
  @moduledoc """
  Coverage-based test selection. A commit's test impact
  (`Tuist.Tests.TestImpact`) is what changed since its baseline, the nearest
  ancestor whose full run recorded per-test coverage evidence, and which
  tests that change reaches. Each invocation that asks for a selection gets
  a selection run (`Tuist.Tests.TestSelectionRun`) that applies the impact to
  the tests it requested: a test runs when its evidence executed a changed
  file, its target changed, it failed at the baseline or it has no evidence;
  otherwise it is skipped. Evidence only narrows what was requested. In dry
  run nothing is skipped, and the tests that would have been skipped but
  failed are the misses.

  The reads here back the Test Selection page and the selection tabs of a
  test run and a test case run; nothing selects yet, so the rows come from
  the seeds or a client that writes them.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestImpact
  alias Tuist.Tests.TestImpactChangedFile
  alias Tuist.Tests.TestSelectionRun
  alias Tuist.Tests.TestSelectionTest

  @selected_reasons ~w(impacted target_changed failed_at_baseline no_evidence run_all)
  @skipped_reasons ~w(unaffected)
  @fallback_reasons ~w(no_baseline baseline_too_far deepen_budget_exhausted timeout platform_mismatch)

  @doc "Why a selection run selects a test (`TestSelectionTest.reason`)."
  def selected_reasons, do: @selected_reasons

  @doc "Why a selection run skips a test (`TestSelectionTest.reason`)."
  def skipped_reasons, do: @skipped_reasons

  @doc "Why a selection run selected every test it requested (`TestSelectionRun.fallback_reason`)."
  def fallback_reasons, do: @fallback_reasons

  defp runs, do: from(r in TestSelectionRun, hints: ["FINAL"])

  @doc """
  The project's selection runs over a period: totals, their trend against
  the period before, and per-bucket series (hours for a period of two days
  or less, days otherwise) of runs, selected, skipped and missed tests, and
  skip rate. The end is carried to the close of its second, as the date
  picker's periods are in whole seconds.
  """
  def analytics(project_id, {start_datetime, end_datetime}) do
    until = DateTime.add(end_datetime, 1, :second)
    bucket = bucket(start_datetime, end_datetime)
    format = bucket_format(bucket)

    rows =
      from(r in runs(),
        where: r.project_id == ^project_id,
        where: r.inserted_at >= ^start_datetime and r.inserted_at < ^until,
        group_by: fragment("formatDateTime(?, ?)", r.inserted_at, ^format),
        select: %{
          date: fragment("formatDateTime(?, ?)", r.inserted_at, ^format),
          runs: count(),
          selected: sum(r.selected_count),
          skipped: sum(r.skipped_count),
          missed: sum(r.missed_count)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(&{&1.date, &1})

    points =
      start_datetime
      |> buckets(end_datetime, bucket)
      |> Enum.map(fn {date, key} ->
        row = Map.get(rows, key, %{runs: 0, selected: 0, skipped: 0, missed: 0})

        %{
          date: date,
          runs: to_integer(row.runs),
          selected: to_integer(row.selected),
          skipped: to_integer(row.skipped),
          missed: to_integer(row.missed),
          skip_rate: skip_rate(to_integer(row.selected), to_integer(row.skipped))
        }
      end)

    span = DateTime.diff(end_datetime, start_datetime, :second)
    current = totals(project_id, start_datetime, until)
    previous = totals(project_id, DateTime.add(start_datetime, -span, :second), start_datetime)

    %{
      totals: current,
      trends:
        Map.new(~w(runs selected skipped skip_rate missed)a, &{&1, trend(Map.get(previous, &1), Map.get(current, &1))}),
      dates: Enum.map(points, & &1.date),
      runs: Enum.map(points, & &1.runs),
      selected: Enum.map(points, & &1.selected),
      skipped: Enum.map(points, & &1.skipped),
      missed: Enum.map(points, & &1.missed),
      skip_rates: Enum.map(points, & &1.skip_rate)
    }
  end

  defp totals(project_id, start_datetime, until) do
    row =
      ClickHouseRepo.one(
        from(r in runs(),
          where: r.project_id == ^project_id,
          where: r.inserted_at >= ^start_datetime and r.inserted_at < ^until,
          select: %{
            runs: count(),
            dry_runs: fragment("countIf(? = 'dry_run')", r.mode),
            fallbacks: fragment("countIf(? != '')", r.fallback_reason),
            selected: sum(r.selected_count),
            skipped: sum(r.skipped_count),
            dry_run_skipped: fragment("sumIf(?, ? = 'dry_run')", r.skipped_count, r.mode),
            missed: sum(r.missed_count),
            skipped_duration: sum(r.skipped_duration)
          }
        )
      ) || %{}

    selected = to_integer(row[:selected])
    skipped = to_integer(row[:skipped])

    %{
      runs: to_integer(row[:runs]),
      dry_runs: to_integer(row[:dry_runs]),
      fallbacks: to_integer(row[:fallbacks]),
      selected: selected,
      skipped: skipped,
      dry_run_skipped: to_integer(row[:dry_run_skipped]),
      missed: to_integer(row[:missed]),
      skipped_duration: to_integer(row[:skipped_duration]),
      skip_rate: skip_rate(selected, skipped)
    }
  end

  @doc "The share of requested tests that were skipped, as a percentage with one decimal."
  def skip_rate(selected, skipped) do
    case selected + skipped do
      0 -> 0.0
      total -> Float.round(skipped / total * 100, 1)
    end
  end

  @doc "The share of would-skip tests that failed, as a percentage with two decimals."
  def miss_rate(_missed, 0), do: 0.0
  def miss_rate(missed, skipped), do: Float.round(missed / skipped * 100, 2)

  defp trend(previous, current) when previous in [0, +0.0] or current in [0, +0.0], do: 0.0
  defp trend(previous, current), do: Float.round((current - previous) / previous * 100, 1)

  defp bucket(start_datetime, end_datetime) do
    if DateTime.diff(end_datetime, start_datetime, :hour) <= 48, do: :hour, else: :day
  end

  defp bucket_format(:hour), do: "%Y-%m-%d %H:00"
  defp bucket_format(:day), do: "%Y-%m-%d"

  defp buckets(start_datetime, end_datetime, :hour) do
    first = %{DateTime.truncate(start_datetime, :second) | minute: 0, second: 0}
    hours = div(DateTime.diff(end_datetime, first, :second), 3600)

    for offset <- 0..hours//1 do
      datetime = DateTime.add(first, offset, :hour)
      {datetime, Calendar.strftime(datetime, "%Y-%m-%d %H:00")}
    end
  end

  defp buckets(start_datetime, end_datetime, :day) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.map(&{&1, Date.to_iso8601(&1)})
  end

  @doc """
  A page of the project's selection runs, newest first. Options: `:search`
  (a commit SHA prefix, or part of a branch, scheme or test plan name),
  `:mode` (`dry_run` or `enabled`), `:fallback` (`true` for the runs that
  ran everything), `:page` and `:page_size`. Returns `{rows,
  %{current_page, total_pages, total_count}}`.
  """
  def list_runs(project_id, opts \\ []) do
    runs()
    |> where([r], r.project_id == ^project_id)
    |> filter_run_search(Keyword.get(opts, :search))
    |> filter_field(:mode, Keyword.get(opts, :mode))
    |> filter_fallback(Keyword.get(opts, :fallback))
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> paginate(opts)
  end

  defp filter_run_search(query, search) when search in [nil, ""], do: query

  defp filter_run_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [r],
      fragment("startsWith(?, ?)", r.git_commit_sha, ^String.downcase(term)) or
        fragment("positionCaseInsensitive(?, ?) > 0", r.git_branch, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", r.scheme, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", r.test_plan, ^term)
    )
  end

  defp filter_fallback(query, true), do: where(query, [r], r.fallback_reason != "")
  defp filter_fallback(query, _fallback), do: query

  @doc "A selection run of the project, by its id."
  def get_run(project_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %TestSelectionRun{} = run <-
           ClickHouseRepo.one(from(r in runs(), where: r.project_id == ^project_id and r.id == ^id, limit: 1)) do
      {:ok, run}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The selection run whose results the test run reported, if any."
  def run_for_test_run(project_id, test_run_id) do
    ClickHouseRepo.one(
      from(r in runs(),
        where: r.project_id == ^project_id and r.test_run_id == ^test_run_id,
        order_by: [desc: r.inserted_at],
        limit: 1
      )
    )
  end

  @doc "The test impact a selection run applied, or `nil` when it fell back without a baseline."
  def get_impact(%TestSelectionRun{baseline_sha: ""}), do: nil

  def get_impact(%TestSelectionRun{project_id: project_id, git_commit_sha: head, baseline_sha: baseline}) do
    ClickHouseRepo.one(
      from(i in TestImpact,
        hints: ["FINAL"],
        where: i.project_id == ^project_id and i.head_sha == ^head and i.baseline_sha == ^baseline,
        limit: 1
      )
    )
  end

  @doc """
  A page of the paths that changed between an impact's baseline and its
  commit. Options: `:search` (part of the path), `:kind`, `:page` and
  `:page_size`. The paths that reach the most tests come first.
  """
  def impact_changed_files(%TestImpact{} = impact, opts \\ []) do
    from(f in TestImpactChangedFile, hints: ["FINAL"])
    |> where_impact(impact)
    |> filter_path(:path, Keyword.get(opts, :search))
    |> filter_field(:kind, Keyword.get(opts, :kind))
    |> order_by([f], desc: f.impacted_tests_count, asc: f.path)
    |> paginate(opts)
  end

  @doc "The changed paths of the impact among `paths`, keyed by path."
  def impact_changed_files_by_path(_impact, []), do: %{}

  def impact_changed_files_by_path(%TestImpact{} = impact, paths) do
    from(f in TestImpactChangedFile, hints: ["FINAL"], where: f.path in ^paths)
    |> where_impact(impact)
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.path, &1})
  end

  defp where_impact(query, %TestImpact{project_id: project_id, head_sha: head, baseline_sha: baseline}) do
    where(query, [x], x.project_id == ^project_id and x.head_sha == ^head and x.baseline_sha == ^baseline)
  end

  @doc """
  What a selection run's tests add up to: requested, selected and skipped
  tests, the misses (skipped tests that failed, in dry run), the selected
  tests that never reported a result, and the number of tests per decision
  and reason.
  """
  def run_summary(%TestSelectionRun{} = run) do
    rows =
      ClickHouseRepo.all(
        from(t in run_tests_query(run),
          group_by: [t.decision, t.reason],
          select: %{decision: t.decision, reason: t.reason, count: count()}
        )
      )

    outcomes =
      if is_nil(run.test_run_id) do
        %{missed: 0, not_run: 0, failed: 0, reported: false}
      else
        row =
          ClickHouseRepo.one(
            from(t in run_tests_query(run),
              left_join: o in subquery(outcomes_query(run)),
              on: o.test_case_id == t.test_case_id,
              select: %{
                missed: fragment("countIf(? = 'skipped' AND ? = 'failure')", t.decision, o.status),
                not_run: fragment("countIf(? = 'selected' AND ifNull(?, '') = '')", t.decision, o.status),
                failed: fragment("countIf(? = 'failure')", o.status)
              }
            )
          )

        %{
          missed: to_integer(row.missed),
          not_run: to_integer(row.not_run),
          failed: to_integer(row.failed),
          reported: true
        }
      end

    reasons =
      rows
      |> Enum.map(&%{decision: &1.decision, reason: &1.reason, count: to_integer(&1.count)})
      |> Enum.sort_by(&{&1.decision != "selected", -&1.count, &1.reason})

    Map.merge(outcomes, %{
      requested: run.requested_count,
      selected: run.selected_count,
      skipped: run.skipped_count,
      skip_rate: skip_rate(run.selected_count, run.skipped_count),
      reasons: reasons
    })
  end

  @doc """
  A page of a selection run's tests with their outcome in the test run that
  reported its results (`nil` when the run reported none for the test).
  Options: `:search` (part of the module, suite or test name), `:decision`
  (`selected` or `skipped`), `:flag` (`missed` or `not_run`), `:shard`,
  `:sort_by` (`decision`, `name`, `shard` or `duration`), `:sort_order`,
  `:page` and `:page_size`.
  """
  def run_tests(%TestSelectionRun{} = run, opts \\ []) do
    query =
      run
      |> run_tests_query()
      |> filter_test_search(Keyword.get(opts, :search))
      |> filter_field(:decision, Keyword.get(opts, :decision))
      |> filter_shard(Keyword.get(opts, :shard))
      |> with_outcomes(run)
      |> filter_flag(Keyword.get(opts, :flag), run)
      |> sort_tests(Keyword.get(opts, :sort_by, "decision"), Keyword.get(opts, :sort_order, "asc"))

    {rows, meta} = paginate(query, opts)
    {Enum.map(rows, &normalize_outcome/1), meta}
  end

  @doc "One of a selection run's tests, by its test case id, with its outcome."
  def get_run_test(%TestSelectionRun{} = run, test_case_id) do
    with {:ok, test_case_id} <- Ecto.UUID.cast(test_case_id),
         row when not is_nil(row) <-
           run
           |> run_tests_query()
           |> where([t], t.test_case_id == ^test_case_id)
           |> with_outcomes(run)
           |> limit(1)
           |> ClickHouseRepo.one() do
      {:ok, normalize_outcome(row)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp run_tests_query(%TestSelectionRun{id: id, project_id: project_id}) do
    from(t in TestSelectionTest, where: t.project_id == ^project_id and t.selection_run_id == ^id)
  end

  defp with_outcomes(query, %TestSelectionRun{test_run_id: nil}),
    do: select(query, [t], %{test: t, status: "", test_case_run_id: ""})

  defp with_outcomes(query, run) do
    from(t in query,
      left_join: o in subquery(outcomes_query(run)),
      on: o.test_case_id == t.test_case_id,
      select: %{test: t, status: o.status, test_case_run_id: o.test_case_run_id}
    )
  end

  # A test's outcome in the run: failed if any of its attempts failed,
  # passed if one passed, skipped otherwise.
  defp outcomes_query(%TestSelectionRun{project_id: project_id, test_run_id: test_run_id}) do
    from(c in TestCaseRun,
      where: c.project_id == ^project_id and c.test_run_id == ^test_run_id and not is_nil(c.test_case_id),
      group_by: fragment("assumeNotNull(?)", c.test_case_id),
      select: %{
        test_case_id: fragment("assumeNotNull(?)", c.test_case_id),
        status:
          fragment(
            "multiIf(countIf(? = 'failure') > 0, 'failure', countIf(? = 'success') > 0, 'success', 'skipped')",
            c.status,
            c.status
          ),
        test_case_run_id: fragment("toString(argMax(?, ?))", c.id, c.ran_at)
      }
    )
  end

  defp normalize_outcome(%{test: test, status: status, test_case_run_id: test_case_run_id}) do
    status = if status in [nil, ""], do: nil, else: status

    test
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.merge(%{
      outcome: status,
      test_case_run_id: if(status, do: test_case_run_id)
    })
  end

  defp filter_flag(query, "missed", %TestSelectionRun{test_run_id: test_run_id}) when not is_nil(test_run_id),
    do: where(query, [t, o], t.decision == "skipped" and o.status == "failure")

  defp filter_flag(query, "not_run", %TestSelectionRun{test_run_id: test_run_id}) when not is_nil(test_run_id),
    do: where(query, [t, o], t.decision == "selected" and fragment("ifNull(?, '') = ''", o.status))

  defp filter_flag(query, _flag, _run), do: query

  defp filter_shard(query, shard) when is_integer(shard),
    do: where(query, [t], t.decision == "selected" and t.shard_index == ^shard)

  defp filter_shard(query, _shard), do: query

  defp sort_tests(query, "name", "desc"), do: order_by(query, [t], desc: t.module_name, desc: t.suite_name, desc: t.name)

  defp sort_tests(query, "name", _order), do: order_by(query, [t], asc: t.module_name, asc: t.suite_name, asc: t.name)

  defp sort_tests(query, "duration", "asc"),
    do: order_by(query, [t], asc: t.estimated_duration_ms, asc: t.module_name, asc: t.name)

  defp sort_tests(query, "duration", _order),
    do: order_by(query, [t], desc: t.estimated_duration_ms, asc: t.module_name, asc: t.name)

  defp sort_tests(query, "shard", order) do
    direction = if order == "desc", do: :desc, else: :asc
    order_by(query, [t], [{:asc, t.decision}, {^direction, t.shard_index}, {:asc, t.module_name}, {:asc, t.name}])
  end

  # Selected first: what the invocation executes is what a reader checks
  # first.
  defp sort_tests(query, _decision, "desc"),
    do: order_by(query, [t], desc: t.decision, asc: t.module_name, asc: t.suite_name, asc: t.name)

  defp sort_tests(query, _decision, _order),
    do: order_by(query, [t], asc: t.decision, asc: t.module_name, asc: t.suite_name, asc: t.name)

  @doc """
  A selection run's shards: for each, the tests planned on it and their
  estimated duration, and, once the run reported, how many ran, failed and
  never reported a result.
  """
  def run_shards(%TestSelectionRun{} = run) do
    query = where(run_tests_query(run), [t], t.decision == "selected")

    rows =
      if is_nil(run.test_run_id) do
        ClickHouseRepo.all(
          from(t in query,
            group_by: t.shard_index,
            select: %{
              shard_index: t.shard_index,
              planned: count(),
              estimated_duration: sum(t.estimated_duration_ms),
              ran: 0,
              failed: 0,
              not_run: 0
            }
          )
        )
      else
        ClickHouseRepo.all(
          from(t in query,
            left_join: o in subquery(outcomes_query(run)),
            on: o.test_case_id == t.test_case_id,
            group_by: t.shard_index,
            select: %{
              shard_index: t.shard_index,
              planned: count(),
              estimated_duration: sum(t.estimated_duration_ms),
              ran: fragment("countIf(ifNull(?, '') != '')", o.status),
              failed: fragment("countIf(? = 'failure')", o.status),
              not_run: fragment("countIf(ifNull(?, '') = '')", o.status)
            }
          )
        )
      end

    rows
    |> Enum.map(fn row ->
      Map.new(row, fn {key, value} -> {key, if(is_integer(value), do: value, else: to_integer(value))} end)
    end)
    |> Enum.sort_by(& &1.shard_index)
  end

  @doc "A selection run's tests per test target: requested, selected and skipped, most selected first."
  def run_targets(%TestSelectionRun{} = run) do
    from(t in run_tests_query(run),
      group_by: t.module_name,
      select: %{
        module_name: t.module_name,
        requested: count(),
        selected: fragment("countIf(? = 'selected')", t.decision),
        skipped: fragment("countIf(? = 'skipped')", t.decision),
        estimated_skipped_duration: fragment("sumIf(?, ? = 'skipped')", t.estimated_duration_ms, t.decision),
        reasons: fragment("groupUniqArrayIf(?, ? = 'selected')", t.reason, t.decision)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        row
        | requested: to_integer(row.requested),
          selected: to_integer(row.selected),
          skipped: to_integer(row.skipped),
          estimated_skipped_duration: to_integer(row.estimated_skipped_duration)
      }
    end)
    |> Enum.sort_by(&{-&1.selected, &1.module_name})
  end

  @doc """
  The files a test executed in its baseline, from the baseline's per-test
  coverage evidence: the paths of its `test` scope in the coverage of the
  baseline commit's test runs.
  """
  def baseline_covered_paths(project_id, baseline_sha, %{module_name: module, suite_name: suite, name: name})
      when baseline_sha != "" do
    scope_id = Enum.join([module, suite, name], "\u001F")

    ClickHouseRepo.all(
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.scope_kind == "test" and f.scope_id == ^scope_id,
        where:
          f.git_commit_sha == ^baseline_sha or f.test_run_id in subquery(baseline_test_runs(project_id, baseline_sha)),
        distinct: true,
        select: f.path,
        order_by: f.path
      )
    )
  end

  def baseline_covered_paths(_project_id, _baseline_sha, _test), do: []

  defp baseline_test_runs(project_id, sha) do
    from(r in CoverageRun, where: r.project_id == ^project_id and r.git_commit_sha == ^sha, select: r.test_run_id)
  end

  @doc """
  A page of the project's default-branch commits that measured coverage,
  newest first, with what makes each one usable as a baseline: whether its
  coverage is complete, the schemes it measured fully and partly, how many
  tests recorded per-test evidence, and how many selection runs used it.
  """
  def baselines(project, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      from(c in CoverageCommit,
        where: c.project_id == ^project.id and c.git_branch == ^project.default_branch and c.executable_lines > 0
      )

    total_count = Repo.aggregate(query, :count)

    commits =
      Repo.all(from(c in query, order_by: [desc: c.ran_at], limit: ^page_size, offset: ^((page - 1) * page_size)))

    shas = Enum.map(commits, & &1.git_commit_sha)
    evidence = evidence_counts(project.id, commits)
    used = baseline_usage(project.id, shas)

    rows =
      Enum.map(commits, fn commit ->
        tests = Map.get(evidence, commit.git_commit_sha, 0)

        %{
          git_commit_sha: commit.git_commit_sha,
          git_branch: commit.git_branch,
          ran_at: commit.ran_at,
          complete: commit.complete,
          schemes: Enum.sort(commit.schemes),
          partial_schemes: Enum.sort(commit.partial_schemes),
          evidence_tests: tests,
          selection_runs: Map.get(used, commit.git_commit_sha, 0),
          status: baseline_status(commit, tests)
        }
      end)

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp baseline_status(%{complete: false}, _tests), do: "incomplete"
  defp baseline_status(_commit, 0), do: "no_test_evidence"
  defp baseline_status(%{partial_schemes: [_ | _]}, _tests), do: "partial"
  defp baseline_status(_commit, _tests), do: "baseline"

  defp evidence_counts(_project_id, []), do: %{}

  defp evidence_counts(project_id, commits) do
    run_ids = Enum.flat_map(commits, & &1.test_run_ids)
    commit_by_run = Map.new(for commit <- commits, id <- commit.test_run_ids, do: {id, commit.git_commit_sha})

    if run_ids == [] do
      %{}
    else
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.scope_kind == "test" and f.test_run_id in ^run_ids,
        group_by: [f.test_run_id, f.scope_id],
        select: {f.test_run_id, f.scope_id}
      )
      |> ClickHouseRepo.all()
      |> Enum.group_by(fn {run_id, _scope} -> Map.get(commit_by_run, run_id) end, &elem(&1, 1))
      |> Map.new(fn {sha, scopes} -> {sha, scopes |> Enum.uniq() |> length()} end)
    end
  end

  defp baseline_usage(_project_id, []), do: %{}

  defp baseline_usage(project_id, shas) do
    from(r in runs(),
      where: r.project_id == ^project_id and r.baseline_sha in ^shas,
      group_by: r.baseline_sha,
      select: {r.baseline_sha, count()}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {sha, count} -> {sha, to_integer(count)} end)
  end

  @doc "Whether any test run of the commit reported coverage."
  def coverage?(_project_id, ""), do: false

  def coverage?(project_id, sha) do
    from(r in CoverageRun,
      where: r.project_id == ^project_id and r.git_commit_sha == ^sha,
      select: 1,
      limit: 1
    )
    |> ClickHouseRepo.one()
    |> is_integer()
  end

  defp filter_test_search(query, search) when search in [nil, ""], do: query

  defp filter_test_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [t],
      fragment("positionCaseInsensitive(?, ?) > 0", t.module_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", t.suite_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", t.name, ^term)
    )
  end

  defp filter_path(query, _field, search) when search in [nil, ""], do: query

  defp filter_path(query, field, search),
    do: where(query, [x], fragment("positionCaseInsensitive(?, ?) > 0", field(x, ^field), ^String.trim(search)))

  defp filter_field(query, _field, value) when value in [nil, "", "any"], do: query
  defp filter_field(query, field, value), do: where(query, [x], field(x, ^field) == ^value)

  defp paginate(query, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    total_count =
      query
      |> exclude(:order_by)
      |> exclude(:select)
      |> select([x], count())
      |> ClickHouseRepo.one()
      |> to_integer()

    rows =
      query
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> ClickHouseRepo.all()

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp ceil_div(count, size), do: div(count + size - 1, size)

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
