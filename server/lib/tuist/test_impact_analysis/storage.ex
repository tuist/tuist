defmodule Tuist.TestImpactAnalysis.Storage do
  @moduledoc """
  Writes and reads coverage-based test selection's diffs and impact runs.
  What a run decided per test is stored as bitmaps
  (`Tuist.TestImpactAnalysis.Decision`). Like shard plans, they are written to and read back from
  `IngestRepo`, with its retries: the client creates an impact run and asks for
  a shard plan pointing to it seconds apart, and `IngestRepo` is the
  deployment that took the write.
  """
  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.TestImpactAnalysis.BuildSystem
  alias Tuist.TestImpactAnalysis.Diff
  alias Tuist.TestImpactAnalysis.Run

  @changed_files_limit 5_000
  @build_context_value_limit 1_024

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
  Records an impact run. `rule_trace` entries are maps with `rule`,
  `selected`, `skipped` and `verdict`; `build_context` keeps only the keys
  the server knows, each value capped in length.
  """
  def create_run(attrs) do
    attrs =
      attrs
      |> Map.put_new_lazy(:id, &UUIDv7.generate/0)
      |> Map.put(:inserted_at, NaiveDateTime.utc_now())
      |> Map.update(:build_context, %{}, &build_context/1)
      |> Map.update(:rule_trace, [], fn trace ->
        Enum.map(trace, &{&1.rule, &1.selected, &1.skipped, &1.verdict})
      end)
      |> Map.update(:dirty_files, [], fn files ->
        files |> Enum.take(@changed_files_limit) |> Enum.map(&{&1.path, &1.status, Map.get(&1, :blob) || ""})
      end)

    with {:ok, run} <- attrs |> Run.create_changeset() |> Ecto.Changeset.apply_action(:insert) do
      {:ok, _} = IngestRepo.insert(run)
      # Like a run read back, which doesn't load the files.
      {:ok, run |> with_rule_trace_maps() |> Map.put(:dirty_files, [])}
    end
  end

  @doc """
  The uncommitted changes a run from a dirty checkout stored (`Run.dirty_files`),
  as `%{path, status, blob}` maps: empty for any other run, for a client that
  didn't mark them, and once they expired.
  """
  def dirty_files(project_id, id) do
    query =
      from(r in Run,
        where: r.project_id == ^project_id and r.id == ^id,
        select: r.dirty_files,
        limit: 1
      )

    Enum.map(IngestRepo.with_retry(fn -> IngestRepo.one(query) end) || [], fn {path, status, blob} ->
      %{path: path, status: status, blob: blob}
    end)
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
  What the project's impact runs among `ids` skipped, for those that skipped
  anything: `:tests` when their decision skipped single tests, `:modules`
  when only modules hashing found unchanged were skipped. Read off the run's
  counts rather than its stored decision, which can be incomplete: its
  `skipped_count` holds the tests of `skipped_modules` and those the
  decision skipped.
  """
  def skips(_project_id, []), do: %{}

  def skips(project_id, ids) do
    query =
      from(r in Run,
        where: r.project_id == ^project_id and r.id in ^ids,
        group_by: r.id,
        having: max(r.skipped_count) > 0,
        select: {r.id, fragment("max(?) > max(arraySum(mapValues(?)))", r.skipped_count, r.skipped_modules)}
      )

    fn -> IngestRepo.all(query) end
    |> IngestRepo.with_retry()
    |> Map.new(fn {id, tests?} -> {id, if(tests? in [true, 1], do: :tests, else: :modules)} end)
  end

  defp build_context(context) do
    for {key, value} <- context,
        key = to_string(key),
        key in BuildSystem.context_keys(),
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
