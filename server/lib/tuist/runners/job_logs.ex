defmodule Tuist.Runners.JobLogs do
  @moduledoc """
  ClickHouse-backed per-line log store for runner jobs.

  Writes are append-only batches from the log-ingest endpoint
  (`IngestRepo.insert_all/2`); reads are single-job, time-windowed
  scans served by the `(workflow_job_id, line_number)` order key.

  The shipper delivers chunks at-least-once, so an append can repeat
  a `(workflow_job_id, line_number)` row on retry. The
  ReplacingMergeTree dedup on that key collapses the duplicate; reads
  use `FINAL` so the dedup is visible immediately. `FINAL` is cheap
  here because every query is scoped to a single `workflow_job_id`
  (the order-key prefix), unlike the multi-row `runner_jobs` reads
  that deliberately avoid it.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobLog
  alias Tuist.Utilities.DateFormatter

  @doc """
  Appends a batch of log lines. Each entry is a map carrying
  `:workflow_job_id`, `:account_id`, `:line_number`, `:ts`, and
  `:message`. `:inserted_at` is stamped here as the RMT version so
  a retried batch resolves to the latest write.
  """
  def append([]), do: :ok

  def append(lines) when is_list(lines) do
    now = DateTime.utc_now()

    rows = Enum.map(lines, &Map.put(&1, :inserted_at, now))
    IngestRepo.insert_all(JobLog, rows)
    :ok
  end

  @doc """
  Lists a job's log lines in display order. `:limit` / `:offset`
  page the stream — logs can be large, so callers window it. Returns
  maps with `:line_number`, `:ts`, `:message`.
  """
  def list_for_job(workflow_job_id, opts \\ []) when is_integer(workflow_job_id) do
    limit = Keyword.get(opts, :limit, 1000)
    offset = Keyword.get(opts, :offset, 0)

    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> order_by([l], asc: l.line_number)
    |> limit(^limit)
    |> offset(^offset)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
  end

  @doc """
  The most recent `limit` lines of a job, in ascending display order.
  This is what the Logs view loads on mount — a tail, not the whole
  stream — so a job with hundreds of thousands of lines doesn't pull
  them all into memory.
  """
  def recent(workflow_job_id, limit) when is_integer(workflow_job_id) and is_integer(limit) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> order_by([l], desc: l.line_number)
    |> limit(^limit)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  @doc """
  The `limit` lines immediately before `before_line_number`, ascending
  — the previous page when the user clicks "Load older logs".
  """
  def older(workflow_job_id, before_line_number, limit)
      when is_integer(workflow_job_id) and is_integer(before_line_number) and is_integer(limit) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number)
    |> order_by([l], desc: l.line_number)
    |> limit(^limit)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  @doc """
  Case-insensitive substring search across a job's full log (every
  captured line, not just the loaded tail). Returns up to `limit`
  matching lines in ascending order.
  """
  def search(workflow_job_id, term, limit \\ 500)

  def search(_workflow_job_id, "", _limit), do: []

  def search(workflow_job_id, term, limit) when is_integer(workflow_job_id) and is_binary(term) and is_integer(limit) do
    pattern = "%" <> escape_like(term) <> "%"

    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id and fragment("? ILIKE ?", l.message, ^pattern))
    |> order_by([l], asc: l.line_number)
    |> limit(^limit)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
  end

  # Escape the LIKE wildcards so a user's literal `%` / `_` aren't
  # treated as patterns (ClickHouse LIKE escapes with backslash).
  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  Whether any line exists before `before_line_number` — drives the
  visibility of the "Load older logs" button.
  """
  def has_older?(_workflow_job_id, nil), do: false

  def has_older?(workflow_job_id, before_line_number)
      when is_integer(workflow_job_id) and is_integer(before_line_number) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number)
    |> select([l], 1)
    |> limit(1)
    |> ClickHouseRepo.one()
    |> is_integer()
  end

  @doc """
  Folds `fun` over a job's full log forward in batches (cursor on
  `line_number`), threading `acc` through. Used by the download
  endpoint to stream the whole log into a chunked response without
  materialising it in memory.
  """
  def reduce(workflow_job_id, batch_size, acc, fun)
      when is_integer(workflow_job_id) and is_integer(batch_size) and is_function(fun, 2) do
    reduce_from(workflow_job_id, 0, batch_size, acc, fun)
  end

  defp reduce_from(workflow_job_id, after_line_number, batch_size, acc, fun) do
    batch =
      JobLog
      |> from(hints: ["FINAL"])
      |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number > ^after_line_number)
      |> order_by([l], asc: l.line_number)
      |> limit(^batch_size)
      |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
      |> ClickHouseRepo.all()

    case batch do
      [] ->
        acc

      lines ->
        reduce_from(workflow_job_id, List.last(lines).line_number, batch_size, fun.(lines, acc), fun)
    end
  end

  # Cap on the total lines loaded per per-step grouping call. Marker
  # detection has to walk the full log, so we put a ceiling here to
  # bound memory + the ClickHouse fetch. 200k covers virtually every
  # job we expect to see; beyond that the UI degrades to "everything
  # under the first step" and the user still has the Logs tab tail.
  @group_by_step_line_cap 200_000

  @doc """
  Groups a job's log lines by step using GitHub's `##[group]Run`
  markers. Returns `%{step_number => [%{line_number, ts, message}]}`.

  ## Why markers, not timestamp windows

  GitHub stamps each step's `started_at` / `completed_at` at second
  resolution. Adjacent steps that finish in under a second (very
  common: `echo` statements, env setup) share the same second, so a
  `[step.started_at, next_step.started_at)` window collapses to zero
  width and the step row stays blank. GitHub's runner emits a
  literal `##[group]Run …` line per user-defined `run:` step, in
  order, into the log it returns from the Logs API. Slicing on those
  markers gives 1:1 alignment with `workflow_job.steps` regardless
  of how fast each step ran.

  ## Anchoring the auto-injected steps

  "Set up job" and "Complete job" never get a `##[group]Run` marker.
  They're anchored positionally:

    * The first step (if `step_count > marker_count`) absorbs every
      line before the first `##[group]Run` marker — that's the
      runner banner, token-permission group, prepare-workflow-dir
      lines, etc.
    * The last step (if `step_count > marker_count + 1`) absorbs
      everything from the first line whose `ts` is at or after its
      own `started_at` — the cleanup phase ("Cleaning up orphan
      processes", etc.). This is the one place we still fall back
      to GitHub's coordinator timestamp; the boundary is
      coarse-grained (cleanup happens seconds after the last user
      step's last line), so second-resolution is enough.
  """
  def lines_grouped_by_step(workflow_job_id, steps) when is_integer(workflow_job_id) and is_list(steps) do
    steps_sorted = Enum.sort_by(steps, & &1.number)
    lines = list_for_job(workflow_job_id, limit: @group_by_step_line_cap)
    derive_step_lines(lines, steps_sorted)
  end

  defp derive_step_lines([], steps_sorted) do
    Map.new(steps_sorted, fn step -> {step.number, []} end)
  end

  defp derive_step_lines(_lines, []) do
    %{}
  end

  defp derive_step_lines(lines, steps_sorted) do
    run_indices = find_run_indices(lines)

    if run_indices == [] do
      # No `##[group]Run` markers — single-step job, or the runner
      # never reached a user step. Lump everything under the first
      # step so the UI still surfaces something.
      first = List.first(steps_sorted)

      Map.new(steps_sorted, fn step ->
        if step.number == first.number, do: {step.number, lines}, else: {step.number, []}
      end)
    else
      slice_by_markers(lines, steps_sorted, run_indices)
    end
  end

  defp find_run_indices(lines) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      if String.starts_with?(line.message, "##[group]Run "), do: [idx], else: []
    end)
  end

  defp slice_by_markers(lines, steps_sorted, run_indices) do
    total = length(lines)
    {setup_steps, user_steps, teardown_steps} = partition_steps(steps_sorted, length(run_indices))
    last_user_end = end_of_last_user_step(lines, total, teardown_steps)

    ranges =
      %{}
      |> Map.merge(setup_ranges(setup_steps, run_indices))
      |> Map.merge(user_ranges(user_steps, run_indices, last_user_end, setup_steps != []))
      |> Map.merge(teardown_ranges(teardown_steps, last_user_end, total))

    materialise(steps_sorted, ranges, lines)
  end

  # Split the ordered step list into (setup, user, teardown) buckets
  # by where the `##[group]Run` markers fall. GitHub's contract: 1
  # auto setup step at the head, N user-Run steps in the middle, 1
  # auto teardown step at the tail. Anything that doesn't fit (rare:
  # cancelled job with no user-Run, or a custom workflow that hand-
  # rolls the steps) degrades to "no setup / all user / no teardown".
  defp partition_steps(steps_sorted, user_step_count) do
    step_count = length(steps_sorted)

    cond do
      step_count <= user_step_count ->
        {[], Enum.take(steps_sorted, user_step_count), []}

      step_count == user_step_count + 1 ->
        {Enum.take(steps_sorted, 1), Enum.slice(steps_sorted, 1, user_step_count), []}

      true ->
        {
          Enum.take(steps_sorted, 1),
          Enum.slice(steps_sorted, 1, user_step_count),
          Enum.drop(steps_sorted, 1 + user_step_count)
        }
    end
  end

  defp end_of_last_user_step(_lines, total, []), do: total - 1

  defp end_of_last_user_step(lines, total, teardown_steps) do
    compute_last_user_end(lines, total, teardown_steps)
  end

  defp materialise(steps_sorted, ranges, lines) do
    Map.new(steps_sorted, fn step ->
      case Map.get(ranges, step.number) do
        {s, e} when is_integer(s) and is_integer(e) and e >= s and s >= 0 ->
          {step.number, Enum.slice(lines, s..e)}

        _ ->
          {step.number, []}
      end
    end)
  end

  defp setup_ranges([], _run_indices), do: %{}

  defp setup_ranges([first | rest], run_indices) do
    first_run = List.first(run_indices)
    ranges = %{first.number => {0, first_run - 1}}
    Enum.reduce(rest, ranges, fn step, acc -> Map.put(acc, step.number, nil) end)
  end

  defp user_ranges(user_steps, run_indices, last_user_end, has_setup) do
    user_step_count = length(user_steps)

    user_steps
    |> Enum.with_index()
    |> Map.new(fn {step, idx} ->
      start_idx =
        if idx == 0 and not has_setup,
          do: 0,
          else: Enum.at(run_indices, idx)

      end_idx =
        if idx == user_step_count - 1,
          do: last_user_end,
          else: Enum.at(run_indices, idx + 1) - 1

      {step.number, {start_idx, end_idx}}
    end)
  end

  defp teardown_ranges([], _last_user_end, _total), do: %{}

  defp teardown_ranges([first | rest], last_user_end, total) do
    ranges = %{first.number => {last_user_end + 1, total - 1}}
    Enum.reduce(rest, ranges, fn step, acc -> Map.put(acc, step.number, nil) end)
  end

  defp compute_last_user_end(lines, total, [%{started_at: %DateTime{} = teardown_start} | _]) do
    case Enum.find_index(lines, fn line ->
           DateTime.compare(line.ts, teardown_start) != :lt
         end) do
      nil -> total - 1
      0 -> -1
      idx -> idx - 1
    end
  end

  defp compute_last_user_end(_lines, total, _teardown_steps), do: total - 1

  @doc """
  Number of distinct log lines captured for a job.
  """
  def count_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> select([l], count(l.line_number))
    |> ClickHouseRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  Renders a batch of log lines to the plain-text download format —
  one `"<ISO timestamp> <message>"` per line, newline-terminated.
  Shared by the chunked download endpoint and the S3 archive worker so
  a job's logs read identically whichever path served them.
  """
  def encode_lines(lines) when is_list(lines) do
    Enum.map_join(lines, "\n", fn %{ts: ts, message: message} ->
      "#{DateFormatter.format_iso(ts)} #{message}"
    end) <> "\n"
  end

  @doc """
  Pub/Sub topic carrying live log chunks for a job. The ingest
  endpoint broadcasts newly appended lines here; the job detail
  LiveView subscribes for the live tail.
  """
  def topic(workflow_job_id) when is_integer(workflow_job_id), do: "runner_job_logs:#{workflow_job_id}"
end
