defmodule Tuist.Tests.Selections.Query do
  @moduledoc """
  The selective testing reads the API and the MCP tools share, on a test
  run: its selection summary, the tests its coverage-based selection decided
  and the files that changed since its baseline, and on a test case run, why
  the selection kept it. Shapes are in `Tuist.Tests.Selections.Schemas`.

  A run without an impact run (`test_impact_run_id`), or whose impact run is
  past retention, reads as no selection: an empty list, or nil.
  """

  alias Tuist.Tests
  alias Tuist.Tests.RunSelections
  alias Tuist.Tests.Selections

  @doc """
  The run's selection: `strategy` (`coverage` or `module_hash`), the
  `baseline_sha` coverage compared against, and its test counts as test
  selection effectiveness counts them (`Tuist.Tests.RunSelections`): the
  tests in scope (`requested`), those the run executed (`selected`), those
  the selection skipped (`skipped`) and how many of those are `estimated`.
  They're the run's own, a shard's included. Until the run's row is
  recorded, a few seconds after it arrives, a run with an impact run reads
  its impact run's counts, shared by the shards that ran it. Nil when the
  run had no selection.
  """
  def test_run(%{ran_at: %NaiveDateTime{} = ran_at} = test_run) do
    impact_run =
      case Selections.run_for_test_run(test_run.project_id, test_run) do
        {:ok, run} -> run
        _ -> nil
      end

    case {RunSelections.get_run(test_run.project_id, test_run.id, ran_at), impact_run} do
      {nil, nil} ->
        nil

      {nil, run} ->
        estimated = run |> Selections.module_skipped_count() |> min(run.skipped_count)
        summary(run.strategy, run, run.requested_count, run.skipped_count, estimated)

      {row, run} ->
        summary(row.strategy, run, row.scope_tests, row.avoided_tests, row.estimated_tests)
    end
  end

  def test_run(_test_run), do: nil

  defp summary(strategy, impact_run, requested, skipped, estimated) do
    %{
      strategy: strategy,
      baseline_sha: impact_run && blank_to_nil(impact_run.baseline_sha),
      requested: requested,
      selected: requested - skipped,
      skipped: skipped,
      estimated: estimated
    }
  end

  @doc "The selection strategy of each of `test_runs`, by id, as their list rows show it."
  def strategies(_project_id, []), do: %{}
  def strategies(project_id, test_runs), do: RunSelections.strategies(project_id, Enum.map(test_runs, & &1.id))

  @doc """
  A page of the tests the run's coverage-based selection decided
  (`Selections.run_tests/3`): every requested test, those in modules skipped
  by hash included, each with its decision, reason, matched path, shard and
  estimated duration, and its outcome in this run. Options: `decision`
  (`selected` or `skipped`), `reason`, `search` (part of the module, suite or
  test name), `page` and `page_size`.
  """
  def tests(test_run, opts) do
    page = Keyword.fetch!(opts, :page)
    page_size = Keyword.fetch!(opts, :page_size)

    case Selections.run_for_test_run(test_run.project_id, test_run) do
      {:ok, run} ->
        {rows, meta} =
          Selections.run_tests(run, test_run.id,
            decision: Keyword.get(opts, :decision),
            reason: Keyword.get(opts, :reason),
            search: Keyword.get(opts, :search),
            page: page,
            page_size: page_size
          )

        {:ok, %{tests: Enum.map(rows, &test_row/1), pagination_metadata: pagination_metadata(page, page_size, meta)}}

      _ ->
        {:ok, %{tests: [], pagination_metadata: pagination_metadata(page, page_size, %{total_count: 0})}}
    end
  end

  @doc """
  A page of the files that changed between the run's baseline and its
  checkout, those that selected the most tests first, each with whether it is
  a tracked file. Empty when the run had no baseline, ran from a dirty
  checkout (whose diff isn't stored) or its diff expired. Options: `search`
  (part of the path), `page` and `page_size`.
  """
  def changed_files(project, test_run, opts) do
    page = Keyword.fetch!(opts, :page)
    page_size = Keyword.fetch!(opts, :page_size)

    with {:ok, run} <- Selections.run_for_test_run(project.id, test_run),
         diff when not is_nil(diff) <- Selections.get_diff(run) do
      {rows, meta} =
        Selections.changed_files(project, run, diff,
          search: Keyword.get(opts, :search) || "",
          page: page,
          page_size: page_size
        )

      {:ok,
       %{
         changed_files: Enum.map(rows, &changed_file_row/1),
         pagination_metadata: pagination_metadata(page, page_size, meta)
       }}
    else
      _ -> {:ok, %{changed_files: [], pagination_metadata: pagination_metadata(page, page_size, %{total_count: 0})}}
    end
  end

  @doc """
  Why the run's coverage-based selection kept a test case run's test: its
  decision, reason, the changed path that matched and the shard it was
  planned on. Nil when the run had no such selection.
  """
  def test_case_run(%{test_run_id: test_run_id, test_case_id: test_case_id} = test_case_run)
      when not is_nil(test_run_id) and not is_nil(test_case_id) do
    case Tests.get_test(test_run_id) do
      {:ok, %{project_id: project_id} = test_run} when project_id == test_case_run.project_id ->
        test_case_run(test_run, test_case_run)

      _ ->
        nil
    end
  end

  def test_case_run(_test_case_run), do: nil

  @doc "As `test_case_run/1`, with the test run it ran in already loaded."
  def test_case_run(test_run, %{test_case_id: test_case_id}) when not is_nil(test_case_id) do
    with {:ok, run} <- Selections.run_for_test_run(test_run.project_id, test_run),
         {:ok, test} <- Selections.get_run_test(run, test_run.id, test_case_id) do
      %{
        decision: test.decision,
        reason: test.reason,
        matched_path: blank_to_nil(test.matched_path),
        shard_index: test.shard_index
      }
    else
      _ -> nil
    end
  end

  def test_case_run(_test_run, _test_case_run), do: nil

  defp test_row(test) do
    %{
      test_case_id: test.test_case_id,
      module_name: test.module_name,
      suite_name: test.suite_name,
      name: test.name,
      decision: test.decision,
      reason: test.reason,
      matched_path: blank_to_nil(test.matched_path),
      shard_index: test.shard_index,
      estimated_duration: test.duration,
      outcome: test.outcome,
      test_case_run_id: test.test_case_run_id
    }
  end

  defp changed_file_row(file) do
    %{
      path: file.path,
      status: file.status,
      tracked: file.tracked,
      selected_tests_count: file.selected_tests_count
    }
  end

  defp pagination_metadata(page, page_size, %{total_count: count}) do
    total_pages = div(count + page_size - 1, page_size)

    %{
      current_page: page,
      page_size: page_size,
      total_count: count,
      total_pages: total_pages,
      has_next_page: page < total_pages,
      has_previous_page: page > 1
    }
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
