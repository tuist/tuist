defmodule Tuist.Runners.JobLogs do
  @moduledoc """
  ClickHouse-backed per-line log store for runner jobs.

  Writes are append-only batches from `FetchLogsWorker`
  (`IngestRepo.insert_all/2`); reads are single-job scans served by
  the `(workflow_job_id, line_number)` order key.

  A worker retry can repeat a `(workflow_job_id, line_number)` row,
  so the ReplacingMergeTree dedups on that key with `inserted_at` as
  the version. Reads use the
  `argMax(col, inserted_at) GROUP BY line_number` pattern to surface
  the latest version immediately — same shape as `Tuist.Runners.Jobs`,
  and cheaper than `FINAL` once a multi-batch job spreads its lines
  across many parts.
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

    ClickHouseRepo.all(
      from(l in JobLog,
        where: l.workflow_job_id == ^workflow_job_id,
        group_by: [l.workflow_job_id, l.line_number],
        order_by: [asc: l.line_number],
        limit: ^limit,
        offset: ^offset,
        select: %{
          line_number: l.line_number,
          ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
          message: fragment("argMax(?, ?)", l.message, l.inserted_at)
        }
      )
    )
  end

  @doc """
  The most recent `limit` lines of a job, in ascending display order.
  This is what the Logs view loads on mount — a tail, not the whole
  stream — so a job with hundreds of thousands of lines doesn't pull
  them all into memory.
  """
  def recent(workflow_job_id, limit) when is_integer(workflow_job_id) and is_integer(limit) do
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id,
      group_by: [l.workflow_job_id, l.line_number],
      order_by: [desc: l.line_number],
      limit: ^limit,
      select: %{
        line_number: l.line_number,
        ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
        message: fragment("argMax(?, ?)", l.message, l.inserted_at)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  @doc """
  The `limit` lines immediately before `before_line_number`, ascending
  — the previous page when the user clicks "Load older logs".
  """
  def older(workflow_job_id, before_line_number, limit)
      when is_integer(workflow_job_id) and is_integer(before_line_number) and is_integer(limit) do
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number,
      group_by: [l.workflow_job_id, l.line_number],
      order_by: [desc: l.line_number],
      limit: ^limit,
      select: %{
        line_number: l.line_number,
        ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
        message: fragment("argMax(?, ?)", l.message, l.inserted_at)
      }
    )
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

    ClickHouseRepo.all(
      from(l in JobLog,
        where: l.workflow_job_id == ^workflow_job_id,
        group_by: [l.workflow_job_id, l.line_number],
        having: fragment("argMax(?, ?) ILIKE ?", l.message, l.inserted_at, ^pattern),
        order_by: [asc: l.line_number],
        limit: ^limit,
        select: %{
          line_number: l.line_number,
          ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
          message: fragment("argMax(?, ?)", l.message, l.inserted_at)
        }
      )
    )
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
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number,
      select: 1,
      limit: 1
    )
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
      ClickHouseRepo.all(
        from(l in JobLog,
          where: l.workflow_job_id == ^workflow_job_id and l.line_number > ^after_line_number,
          group_by: [l.workflow_job_id, l.line_number],
          order_by: [asc: l.line_number],
          limit: ^batch_size,
          select: %{
            line_number: l.line_number,
            ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
            message: fragment("argMax(?, ?)", l.message, l.inserted_at)
          }
        )
      )

    case batch do
      [] ->
        acc

      lines ->
        reduce_from(workflow_job_id, List.last(lines).line_number, batch_size, fun.(lines, acc), fun)
    end
  end

  @doc """
  For each step, the `{first_line_number, last_line_number}` slice
  of the job's log that belongs to that step, or `nil` if no slice
  could be derived (e.g. the step ran but produced no captured
  output). The Steps card uses this to render headers eagerly and
  fetch each step's lines via `list_step_lines/3` only on expand,
  so a 200k-line job never materialises in the socket.

  Three small ClickHouse queries: the job's `max(line_number)`, the
  `##[group]Run` marker line numbers, and (if there's a teardown
  step) the first line at or after its `started_at`. Nothing scans
  the log body.

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
      line before the first `##[group]Run` marker — runner banner,
      token-permission group, prepare-workflow-dir lines, etc.
    * The last step (if `step_count > marker_count + 1`) absorbs
      everything from the first line whose `ts` is at or after its
      own `started_at` — the cleanup phase ("Cleaning up orphan
      processes", etc.). This is the one place we still fall back
      to GitHub's coordinator timestamp; the boundary is coarse-
      grained (cleanup happens seconds after the last user step's
      last line), so second-resolution is enough.
  """
  def step_line_ranges(workflow_job_id, steps) when is_integer(workflow_job_id) and is_list(steps) do
    steps_sorted = Enum.sort_by(steps, & &1.number)

    case {steps_sorted, max_line_number(workflow_job_id)} do
      {[], _} ->
        %{}

      {sorted, nil} ->
        Map.new(sorted, fn step -> {step.number, nil} end)

      {sorted, total_max} ->
        markers = marker_line_numbers(workflow_job_id)
        compute_ranges(sorted, markers, total_max, workflow_job_id)
    end
  end

  @doc """
  Lines whose `line_number` falls in `[first, last]` (inclusive),
  renumbered 1-indexed per step so the Steps card shows "1, 2, 3…"
  regardless of where the step sits in the job-wide sequence —
  matches GitHub's own Steps UI.
  """
  def list_step_lines(workflow_job_id, first_line, last_line)
      when is_integer(workflow_job_id) and is_integer(first_line) and is_integer(last_line) and last_line >= first_line do
    from(l in JobLog,
      where:
        l.workflow_job_id == ^workflow_job_id and
          l.line_number >= ^first_line and
          l.line_number <= ^last_line,
      group_by: [l.workflow_job_id, l.line_number],
      order_by: [asc: l.line_number],
      select: %{
        line_number: l.line_number,
        ts: fragment("argMax(?, ?)", l.ts, l.inserted_at),
        message: fragment("argMax(?, ?)", l.message, l.inserted_at)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {line, idx} -> %{line | line_number: idx} end)
  end

  def list_step_lines(_workflow_job_id, _first_line, _last_line), do: []

  defp compute_ranges(steps_sorted, [], total_max, _workflow_job_id) do
    # No markers — single-step semantics: the first step absorbs
    # the whole log, the rest are unmappable.
    first = List.first(steps_sorted)

    Map.new(steps_sorted, fn step ->
      if step.number == first.number,
        do: {step.number, {1, total_max}},
        else: {step.number, nil}
    end)
  end

  defp compute_ranges(steps_sorted, markers, total_max, workflow_job_id) do
    {setup_steps, user_steps, teardown_steps} = partition_steps(steps_sorted, length(markers))
    last_user_end = end_of_last_user_step(workflow_job_id, total_max, teardown_steps)

    %{}
    |> Map.merge(setup_range(setup_steps, markers))
    |> Map.merge(user_ranges(user_steps, markers, last_user_end, setup_steps != []))
    |> Map.merge(teardown_range(teardown_steps, last_user_end, total_max))
    |> fill_unmapped(steps_sorted)
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

  defp end_of_last_user_step(_workflow_job_id, total_max, []), do: total_max

  defp end_of_last_user_step(workflow_job_id, total_max, [%{started_at: %DateTime{} = teardown_start} | _]) do
    case teardown_anchor_line(workflow_job_id, teardown_start) do
      nil -> total_max
      anchor -> anchor - 1
    end
  end

  defp end_of_last_user_step(_workflow_job_id, total_max, _teardown_steps), do: total_max

  defp setup_range([], _markers), do: %{}

  defp setup_range([first | _rest], [first_marker | _]) do
    if first_marker > 1, do: %{first.number => {1, first_marker - 1}}, else: %{first.number => nil}
  end

  defp user_ranges(user_steps, markers, last_user_end, has_setup) do
    user_step_count = length(user_steps)

    user_steps
    |> Enum.with_index()
    |> Map.new(fn {step, idx} ->
      start_line =
        if idx == 0 and not has_setup,
          do: 1,
          else: Enum.at(markers, idx)

      end_line =
        if idx == user_step_count - 1,
          do: last_user_end,
          else: Enum.at(markers, idx + 1) - 1

      {step.number, valid_range(start_line, end_line)}
    end)
  end

  defp teardown_range([], _last_user_end, _total_max), do: %{}

  defp teardown_range([first | _rest], last_user_end, total_max) do
    %{first.number => valid_range(last_user_end + 1, total_max)}
  end

  defp valid_range(first, last) when is_integer(first) and is_integer(last) and last >= first, do: {first, last}
  defp valid_range(_, _), do: nil

  defp fill_unmapped(ranges, steps_sorted) do
    Enum.reduce(steps_sorted, ranges, fn step, acc ->
      Map.put_new(acc, step.number, nil)
    end)
  end

  defp max_line_number(workflow_job_id) do
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id,
      select: fragment("max(?)", l.line_number)
    )
    |> ClickHouseRepo.one()
    |> case do
      0 -> nil
      value -> value
    end
  end

  # `##[group]Run ` (trailing space) is the literal prefix GitHub's
  # runner emits per user-defined `run:` step. The HAVING runs against
  # the deduped message so a retried row can't slip past the filter.
  defp marker_line_numbers(workflow_job_id) do
    ClickHouseRepo.all(
      from(l in JobLog,
        where: l.workflow_job_id == ^workflow_job_id,
        group_by: [l.workflow_job_id, l.line_number],
        having: fragment("startsWith(argMax(?, ?), '##[group]Run ')", l.message, l.inserted_at),
        order_by: [asc: l.line_number],
        select: l.line_number
      )
    )
  end

  # `ts` comes from the GH log line itself, so a retried row carries
  # an identical ts — no dedup needed for this anchor.
  defp teardown_anchor_line(workflow_job_id, teardown_started_at) do
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id and l.ts >= ^teardown_started_at,
      select: fragment("min(?)", l.line_number)
    )
    |> ClickHouseRepo.one()
    |> case do
      0 -> nil
      value -> value
    end
  end

  @doc """
  Number of distinct log lines captured for a job.
  """
  def count_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    from(l in JobLog,
      where: l.workflow_job_id == ^workflow_job_id,
      select: fragment("uniqExact(?)", l.line_number)
    )
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
