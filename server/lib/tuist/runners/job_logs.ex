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
  of the job's log that belongs to that step, `nil` if the step
  produced no output (e.g. it was skipped), or `:unattributed` if the
  step ran but its output can't be told apart from the rest of the
  log (see below). The Steps card uses this to render headers
  eagerly and fetch each step's lines via `list_step_lines/3` only
  on expand, so a 200k-line job never materialises in the socket.

  Two small ClickHouse queries: the job's `max(line_number)` and the
  handful of structural lines the runner writes around steps.

  ## Step boundaries

  GitHub stamps each step's `started_at` / `completed_at` at second
  resolution, so adjacent fast steps can't be told apart by time.
  Instead, the log is sliced on the first line the runner writes for
  every step it executes:

    * `##[group]Run …` for a main step (`run:` or `uses:`).
    * `Post job cleanup.` for a post step.
    * `##[group]Checking docker version` for "Initialize containers".
    * `Stop and remove container: …` / `Remove container network: …`
      for "Stop containers".
    * `Evaluate and set job outputs` / `Cleaning up orphan processes`
      for "Complete job".

  "Set up job" is everything before the first boundary. The lines the
  runner writes right before a step's header (`Prepare all required
  actions`, action downloads, the job hook notice) belong to that
  step, as in GitHub's own Steps UI. Skipped steps write nothing.

  Composite actions write each nested step between
  `##[start-action …]` and `##[end-action …]`, and nested steps carry
  their own `##[group]Run …` header, so only headers outside those
  pairs start a step.

  When the boundaries don't line up one-to-one with the executed
  steps (background steps, whose output isn't written in step order,
  or a step printing `::group::Run …`), every executed step is
  `:unattributed` instead of showing another step's output. A log
  without any boundary is attributed to the first step.
  """
  def step_line_ranges(workflow_job_id, steps) when is_integer(workflow_job_id) and is_list(steps) do
    steps_sorted = Enum.sort_by(steps, & &1.number)

    case {steps_sorted, max_line_number(workflow_job_id)} do
      {[], _} ->
        %{}

      {sorted, nil} ->
        Map.new(sorted, fn step -> {step.number, nil} end)

      {sorted, total_max} ->
        starts = workflow_job_id |> structural_lines() |> step_start_lines()

        sorted
        |> compute_ranges(starts, total_max)
        |> fill_unmapped(sorted)
    end
  end

  @doc """
  Lines whose `line_number` falls in `[first, last]` (inclusive),
  renumbered 1-indexed per step so the Steps card shows "1, 2, 3…"
  regardless of where the step sits in the job-wide sequence.

  Numbering matches GitHub's own step view: the `##[endgroup]` and
  `##[end-action …]` delimiters are never displayed, so they don't
  take a number and get `line_number: nil`.
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
    |> Enum.map_reduce(0, fn line, displayed ->
      if delimiter_line?(line.message),
        do: {%{line | line_number: nil}, displayed},
        else: {%{line | line_number: displayed + 1}, displayed + 1}
    end)
    |> elem(0)
  end

  def list_step_lines(_workflow_job_id, _first_line, _last_line), do: []

  defp delimiter_line?("##[endgroup]" <> _), do: true
  defp delimiter_line?("##[end-action " <> _), do: true
  defp delimiter_line?(_message), do: false

  defp compute_ranges([first | _], [], total_max), do: %{first.number => {1, total_max}}

  defp compute_ranges(steps_sorted, starts, total_max) do
    executed = Enum.reject(steps_sorted, &(Map.get(&1, :conclusion) == "skipped"))

    if length(executed) == length(starts) + 1 do
      ends = Enum.map(starts, &(&1 - 1)) ++ [total_max]

      executed
      |> Enum.zip(Enum.zip([1 | starts], ends))
      |> Map.new(fn {step, {first, last}} -> {step.number, valid_range(first, last)} end)
    else
      Map.new(executed, fn step -> {step.number, :unattributed} end)
    end
  end

  defp step_start_lines(structural_lines) do
    {starts, _depth, _preamble, _last_kind} =
      Enum.reduce(structural_lines, {[], 0, MapSet.new(), nil}, fn %{line_number: line_number, message: message},
                                                                   {starts, depth, preamble, last_kind} = acc ->
        case {classify(message), depth} do
          {:enter, _} ->
            {starts, depth + 1, preamble, last_kind}

          {:exit, _} ->
            {starts, max(depth - 1, 0), preamble, last_kind}

          {_, nested_depth} when nested_depth > 0 ->
            acc

          {:preamble, _} ->
            {starts, depth, MapSet.put(preamble, line_number), last_kind}

          {{:boundary, kind}, _} when kind in [:stop_containers, :complete] and kind == last_kind ->
            acc

          {{:boundary, kind}, _} ->
            {[first_preamble_line(line_number, preamble) | starts], depth, preamble, kind}
        end
      end)

    Enum.reverse(starts)
  end

  defp first_preamble_line(line_number, preamble) do
    if MapSet.member?(preamble, line_number - 1),
      do: first_preamble_line(line_number - 1, preamble),
      else: line_number
  end

  defp classify("##[start-action" <> _), do: :enter
  defp classify("##[end-action" <> _), do: :exit
  defp classify("##[group]Run " <> _), do: {:boundary, :run}
  defp classify("##[group]Checking docker version"), do: {:boundary, :initialize_containers}
  defp classify("Post job cleanup."), do: {:boundary, :post}
  defp classify("Stop and remove container: " <> _), do: {:boundary, :stop_containers}
  defp classify("Remove container network: " <> _), do: {:boundary, :stop_containers}
  defp classify("Evaluate and set job outputs"), do: {:boundary, :complete}
  defp classify("Cleaning up orphan processes"), do: {:boundary, :complete}
  defp classify(_), do: :preamble

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

  # Every line `classify/1` recognises. Lines that aren't markers or
  # boundaries are the runner's per-step preamble. The HAVING runs
  # against the deduped message so a retried row can't slip past the
  # filter.
  @structural_line_pattern "^(##\\[(start-action|end-action|group\\]Run |group\\]Checking docker version$)|Post job cleanup\\.$|Stop and remove container: |Remove container network: |Evaluate and set job outputs$|Cleaning up orphan processes$|Prepare all required actions$|Getting action download info$|Download action repository |A job (started|completed) hook has been configured)"

  defp structural_lines(workflow_job_id) do
    ClickHouseRepo.all(
      from(l in JobLog,
        where: l.workflow_job_id == ^workflow_job_id,
        group_by: [l.workflow_job_id, l.line_number],
        having: fragment("match(argMax(?, ?), ?)", l.message, l.inserted_at, ^@structural_line_pattern),
        order_by: [asc: l.line_number],
        select: %{
          line_number: l.line_number,
          message: fragment("leftUTF8(argMax(?, ?), 64)", l.message, l.inserted_at)
        }
      )
    )
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
  Pub/Sub topic carrying log-lifecycle events for a job.

  `FetchLogsWorker` broadcasts `:runner_job_logs_ready` once it
  finishes streaming a job's captured log into ClickHouse;
  `ArchiveLogsWorker` broadcasts `:runner_job_log_archived` once it
  stamps `log_archived_at`. The job detail LiveView subscribes so the
  empty state flips to the loaded view, and the "Download logs"
  button appears, without the user having to refresh.
  """
  def topic(workflow_job_id) when is_integer(workflow_job_id), do: "runner_job_logs:#{workflow_job_id}"
end
