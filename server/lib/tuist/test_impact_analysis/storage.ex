defmodule Tuist.TestImpactAnalysis.Storage do
  @moduledoc """
  Writes and reads coverage-based test selection's diffs, impact runs and
  selected tests. Like shard plans, they are written to and read back from
  `IngestRepo`, with its retries: the client creates an impact run and asks for
  a shard plan pointing to it seconds apart, and `IngestRepo` is the
  deployment that took the write.
  """
  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.TestImpactAnalysis.Diff
  alias Tuist.TestImpactAnalysis.Run
  alias Tuist.TestImpactAnalysis.RunTest

  @changed_files_limit 5_000
  @build_context_keys ~w(scheme test_plan destination)
  @build_context_value_limit 1_024
  @insert_chunk_size 10_000

  @doc """
  Stores the diff between a baseline and the checked-out commit. `changed_files`
  are maps with `path`, `status`, `blob` (absent for deleted files) and
  `affected_modules`. Only the first 5,000 are kept; `changed_files_count`,
  which defaults to how many were given, keeps the diff's total size.
  """
  def put_diff(%{project_id: project_id, commit_sha: commit_sha, baseline_sha: baseline_sha} = attrs) do
    changed_files = Map.get(attrs, :changed_files, [])

    IngestRepo.insert_all(Diff, [
      %{
        project_id: project_id,
        commit_sha: commit_sha,
        baseline_sha: baseline_sha,
        changed_files:
          changed_files
          |> Enum.take(@changed_files_limit)
          |> Enum.map(&{&1.path, &1.status, Map.get(&1, :blob) || "", Map.get(&1, :affected_modules) || []}),
        changed_files_count: Map.get(attrs, :changed_files_count) || length(changed_files),
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    :ok
  end

  @doc """
  The stored diff between `baseline_sha` and the checked-out `commit_sha`,
  with its changed files as maps.
  """
  def get_diff(project_id, commit_sha, baseline_sha) do
    query =
      from(d in Diff,
        where: d.project_id == ^project_id and d.commit_sha == ^commit_sha and d.baseline_sha == ^baseline_sha,
        limit: 1
      )

    case IngestRepo.with_retry(fn -> IngestRepo.one(query) end) do
      nil -> {:error, :not_found}
      diff -> {:ok, with_changed_files(diff)}
    end
  end

  @doc """
  The stored diffs of the checked-out `commit_shas`, one per commit and
  baseline, as `get_diff/3` returns them.
  """
  def list_diffs(_project_id, []), do: []

  def list_diffs(project_id, commit_shas) do
    query = from(d in Diff, where: d.project_id == ^project_id and d.commit_sha in ^commit_shas)
    query |> IngestRepo.all() |> Enum.uniq_by(&{&1.commit_sha, &1.baseline_sha}) |> Enum.map(&with_changed_files/1)
  end

  defp with_changed_files(diff) do
    changed_files =
      Enum.map(diff.changed_files, fn {path, status, blob, affected_modules} ->
        %{path: path, status: status, blob: blob, affected_modules: affected_modules}
      end)

    %{diff | changed_files: changed_files}
  end

  @doc """
  Records an impact run and the tests it selected. `rule_trace` entries are
  maps with `rule`, `selected`, `skipped` and `verdict`; `build_context` keeps
  only the keys the server knows, each value capped in length. Each selected
  test is a map with `test_case_id`, `module_name`, `suite_name`, `name`,
  `reason` and optionally `matched_path`. Fallbacks are recorded without tests.
  """
  def create_run(attrs, selected_tests \\ []) do
    now = NaiveDateTime.utc_now()

    attrs =
      attrs
      |> Map.put_new_lazy(:id, &UUIDv7.generate/0)
      |> Map.put(:inserted_at, now)
      |> Map.update(:build_context, %{}, &build_context/1)
      |> Map.update(:rule_trace, [], fn trace ->
        Enum.map(trace, &{&1.rule, &1.selected, &1.skipped, &1.verdict})
      end)

    with {:ok, run} <- attrs |> Run.create_changeset() |> Ecto.Changeset.apply_action(:insert) do
      {:ok, _} = IngestRepo.insert(run)

      selected_tests
      |> Stream.map(fn test ->
        %{
          test_impact_run_id: run.id,
          project_id: run.project_id,
          test_case_id: test.test_case_id,
          module_name: test.module_name,
          suite_name: Map.get(test, :suite_name) || "",
          name: test.name,
          reason: test.reason,
          matched_path: Map.get(test, :matched_path) || "",
          inserted_at: now
        }
      end)
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(RunTest, &1))

      {:ok, with_rule_trace_maps(run)}
    end
  end

  @doc """
  The project's impact run with the given id.
  """
  def get_run(project_id, id) do
    query = from(r in Run, where: r.project_id == ^project_id and r.id == ^id, limit: 1)

    case IngestRepo.with_retry(fn -> IngestRepo.one(query) end) do
      nil -> {:error, :not_found}
      run -> {:ok, with_rule_trace_maps(run)}
    end
  end

  @doc """
  The tests an impact run selected, ordered by module, suite and name.
  """
  def list_run_tests(project_id, test_impact_run_id) do
    query =
      from(t in RunTest,
        where: t.project_id == ^project_id and t.test_impact_run_id == ^test_impact_run_id,
        order_by: [asc: t.module_name, asc: t.suite_name, asc: t.name]
      )

    IngestRepo.with_retry(fn -> IngestRepo.all(query) end)
  end

  defp build_context(context) do
    for {key, value} <- context,
        key = to_string(key),
        key in @build_context_keys,
        is_binary(value),
        into: %{},
        do: {key, String.slice(value, 0, @build_context_value_limit)}
  end

  defp with_rule_trace_maps(run) do
    %{
      run
      | rule_trace:
          Enum.map(run.rule_trace, fn {rule, selected, skipped, verdict} ->
            %{rule: rule, selected: selected, skipped: skipped, verdict: verdict}
          end)
    }
  end
end
