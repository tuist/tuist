defmodule Tuist.RemoteExecution.Actions do
  @moduledoc """
  What ran remotely: one record per action the execution gateway executed,
  on both the scheduled and the leased path.

  The gateway pushes records after the client already has its result, in
  bounded batches and best effort, so a lost record never affects a build
  and a missing record does not prove an action did not run. The server
  never reads the cache for them: the command, environment and the start of
  stdout and stderr are copied when the action runs, within the bounds below,
  which the server applies again whatever the gateway sends. Environment
  values and flag values whose names look like secrets are masked before
  they are stored.

  Records are diagnostics, kept for 90 days. Usage is metered separately in
  `Tuist.RemoteExecution.Usage`.

  A stream longer than its record keeps gets a presigned upload in the
  answer to the record (`log_uploads/2`), and the gateway copies the whole
  stream, or its last 16 MiB when it is longer, from the cache to object
  storage, off the client's path. The copies are run artifacts (`<account>/<project>/runs/<invocation>/`),
  so they expire with the account's plan, sooner than the record; without one
  the record's preview is all there is.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.RemoteExecution.Action
  alias Tuist.RemoteExecution.Settings
  alias Tuist.RemoteExecution.TaskSizes
  alias Tuist.Storage

  @max_records 100
  @max_arguments_bytes 64 * 1024
  @max_log_bytes 16 * 1024
  @max_entries 512
  @max_value_bytes 4096
  @max_field_bytes 256
  @masked "****"
  @phases [
    {:queue_ms, :queued_at, :worker_start_at},
    {:input_fetch_ms, :input_fetch_start_at, :input_fetch_completed_at},
    {:execution_ms, :execution_start_at, :execution_completed_at},
    {:output_upload_ms, :output_upload_start_at, :output_upload_completed_at}
  ]
  @timestamp_names ~w(queued worker_start input_fetch_start input_fetch_completed execution_start execution_completed output_upload_start output_upload_completed worker_completed)
  @summary_fields [
    :operation_id,
    :invocation_id,
    :action_hash,
    :action_size,
    :mnemonic,
    :target,
    :execution_path,
    :memory_gb,
    :cached_result,
    :status_code,
    :exit_code,
    :queued_at,
    :worker_start_at,
    :input_fetch_start_at,
    :input_fetch_completed_at,
    :execution_start_at,
    :execution_completed_at,
    :output_upload_start_at,
    :output_upload_completed_at,
    :worker_completed_at
  ]
  # The dashboard keeps a viewed log in memory, so very long streams keep
  # only their end.
  @log_copy_bytes 16 * 1024 * 1024
  @log_upload_seconds 15 * 60
  @log_streams ~w(stdout stderr)
  @log_page_bytes 64 * 1024
  @log_page_lines 1000
  @max_log_range 64 * 1024
  @max_errors 100
  @key_segment ~r/\A[A-Za-z0-9._-]{1,128}\z/
  @hash ~r/\A[0-9a-f]{64}\z/
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def max_records, do: @max_records
  def phases, do: Enum.map(@phases, &elem(&1, 0))

  @doc """
  Stores a batch of gateway records for `project`. Records without a
  well-formed operation ID, action digest or invocation ID are skipped:
  nothing could find them. Returns how many were accepted.
  """
  def ingest(%Project{} = project, records) when is_list(records) and length(records) <= @max_records do
    now = NaiveDateTime.utc_now()
    rows = for record <- records, row = row(project, record, now), do: row

    if rows != [], do: Action.Buffer.insert_all(rows)
    TaskSizes.record(project, records)
    {:ok, length(rows)}
  end

  def ingest(_project, _records), do: {:error, :invalid_request}

  defp row(project, %{} = record, now) do
    with id when is_binary(id) <- record["operation_id"],
         true <- Regex.match?(@uuid, id),
         hash when is_binary(hash) <- record["action_hash"],
         true <- Regex.match?(@hash, hash),
         invocation when is_binary(invocation) and invocation != "" <- record["invocation_id"],
         true <- byte_size(invocation) <= @max_field_bytes do
      {arguments, truncated} = arguments(record["arguments"])
      {environment_names, environment_values} = pairs(record["environment"], &mask_value/2)
      {platform_names, platform_values} = pairs(record["platform"], fn _name, value -> value end)
      output_paths = strings(record["output_paths"])
      {stdout, stdout_truncated} = log(record, "stdout")
      {stderr, stderr_truncated} = log(record, "stderr")

      Map.merge(
        %{
          operation_id: id,
          account_id: project.account_id,
          project_id: project.id,
          invocation_id: invocation,
          action_hash: hash,
          action_size: integer(record["action_size"]),
          tool_name: field(record["tool_name"]),
          tool_version: field(record["tool_version"]),
          mnemonic: field(record["mnemonic"]),
          target: field(record["target"], @max_value_bytes),
          configuration_id: field(record["configuration_id"]),
          execution_path: if(record["execution_path"] in ["scheduled", "lease"], do: record["execution_path"], else: ""),
          sandbox_id: field(record["sandbox_id"]),
          worker: field(record["worker"]),
          memory_gb: min(ran_in(record), 65_535),
          timeout_ms: integer(record["timeout_ms"]),
          do_not_cache: record["do_not_cache"] == true,
          cached_result: record["cached_result"] == true,
          arguments: arguments,
          arguments_truncated: truncated or record["arguments_truncated"] == true,
          environment_names: environment_names,
          environment_values: environment_values,
          working_directory: field(record["working_directory"], @max_value_bytes),
          platform_names: platform_names,
          platform_values: platform_values,
          output_paths: output_paths,
          output_count: record["output_count"] |> integer() |> min(4_294_967_295) |> max(length(output_paths)),
          status_code: int32(record["status_code"]),
          status_message: field(record["status_message"], @max_value_bytes),
          exit_code: int32(record["exit_code"]),
          stdout: stdout,
          stdout_size: integer(record["stdout_size"]),
          stdout_truncated: stdout_truncated,
          stderr: stderr,
          stderr_size: integer(record["stderr_size"]),
          stderr_truncated: stderr_truncated,
          inserted_at: now
        },
        timestamp_fields(record["timestamps"])
      )
    else
      _ -> nil
    end
  end

  defp row(_project, _record, _now), do: nil

  defp timestamp_fields(%{} = timestamps) do
    Map.new(@timestamp_names, fn name -> {String.to_existing_atom(name <> "_at"), timestamp(timestamps[name])} end)
  end

  defp timestamp_fields(_), do: timestamp_fields(%{})

  # Unix microseconds; zero, absent or implausible values are unavailable.
  defp timestamp(us) when is_integer(us) and us > 0 and us < 4_102_444_800_000_000,
    do: us |> DateTime.from_unix!(:microsecond) |> DateTime.to_naive()

  defp timestamp(_), do: nil

  defp arguments(list) when is_list(list) do
    {kept, _bytes, truncated} =
      list
      |> Enum.filter(&is_binary/1)
      |> mask_arguments()
      |> Enum.reduce_while({[], 0, false}, fn argument, {kept, bytes, _} ->
        if bytes + byte_size(argument) > @max_arguments_bytes,
          do: {:halt, {kept, bytes, true}},
          else: {:cont, {[argument | kept], bytes + byte_size(argument), false}}
      end)

    {Enum.reverse(kept), truncated or length(list) > length(kept)}
  end

  defp arguments(_), do: {[], false}

  @doc """
  Masks the values of flags whose names look like secrets: `--name=value`
  and `NAME=value` when the name contains TOKEN, SECRET, PASSWORD or KEY,
  and the argument after a flag such as `--password` or `--api-key` that
  ends with one of them.
  """
  def mask_arguments(arguments) do
    {masked, _} =
      Enum.map_reduce(arguments, false, fn argument, mask_next ->
        cond do
          mask_next ->
            {@masked, false}

          match = Regex.run(~r/\A(-{0,2}[A-Za-z0-9_.\-]+)=/, argument) ->
            [prefix, name] = match
            {if(secret?(name), do: prefix <> @masked, else: argument), false}

          Regex.match?(~r/\A-{1,2}[A-Za-z0-9_.\-]*(token|secret|password|key)\z/i, argument) ->
            {argument, true}

          true ->
            {argument, false}
        end
      end)

    masked
  end

  defp secret?(name), do: Regex.match?(~r/token|secret|password|key/i, name)

  defp mask_value(name, value), do: if(secret?(name), do: @masked, else: value)

  defp pairs(list, value_fun) when is_list(list) do
    list
    |> Enum.flat_map(fn
      %{"name" => name, "value" => value} when is_binary(name) and is_binary(value) ->
        [{field(name), value_fun.(name, field(value, @max_value_bytes))}]

      _ ->
        []
    end)
    |> Enum.take(@max_entries)
    |> Enum.unzip()
  end

  defp pairs(_list, _value_fun), do: {[], []}

  defp strings(list) when is_list(list),
    do: list |> Enum.filter(&is_binary/1) |> Enum.take(@max_entries) |> Enum.map(&field(&1, @max_value_bytes))

  defp strings(_), do: []

  defp log(record, stream) do
    case record[stream] do
      text when is_binary(text) ->
        kept = String.byte_slice(text, 0, @max_log_bytes)
        {kept, byte_size(kept) < byte_size(text) or record[stream <> "_truncated"] == true}

      _ ->
        {"", false}
    end
  end

  defp field(value, limit \\ @max_field_bytes)
  defp field(value, limit) when is_binary(value), do: String.byte_slice(value, 0, limit)
  defp field(_value, _limit), do: ""

  defp integer(value) when is_integer(value) and value >= 0, do: min(value, 9_223_372_036_854_775_807)
  defp integer(_), do: 0

  defp int32(value) when is_integer(value) and value in -2_147_483_648..2_147_483_647, do: value
  defp int32(_), do: 0

  # The gateway's memory_gb is the size the action asked for; automatic
  # sizing can run it in a bigger VM, which the usage reports.
  defp ran_in(%{"usage" => %{"memory_gb" => gb}}) when is_integer(gb) and gb > 0, do: integer(gb)
  defp ran_in(record), do: integer(record["memory_gb"])

  @doc """
  One page of an invocation's remote actions, without command, environment
  or output. `sort_by` is `duration` (longest first, the default),
  `queued_at` (earliest first) or `completed_at` (latest first);
  `failed: true` keeps actions that exited non-zero or did not complete.
  """
  def list(project_id, invocation_id, attrs \\ %{}) do
    page = max(attrs[:page] || 1, 1)
    page_size = attrs[:page_size] |> Kernel.||(20) |> max(1) |> min(100)
    query = filtered(project_id, invocation_id, attrs)
    total = ClickHouseRepo.one(from(a in query, select: count()))

    actions =
      from(a in query,
        select: map(a, ^@summary_fields),
        limit: ^page_size,
        offset: ^((page - 1) * page_size)
      )
      |> order(attrs[:sort_by], attrs[:sort_order])
      |> ClickHouseRepo.all()
      |> Enum.map(&(&1 |> with_phases() |> Map.put(:vcpus, vcpus(&1.memory_gb))))

    total_pages = if(total == 0, do: 0, else: div(total + page_size - 1, page_size))

    {actions,
     %{
       has_next_page?: page < total_pages,
       has_previous_page?: page > 1,
       current_page: page,
       page_size: page_size,
       total_count: total,
       total_pages: total_pages
     }}
  end

  defp filtered(project_id, invocation_id, attrs) do
    query =
      from(a in Action,
        hints: ["FINAL"],
        where: a.project_id == ^project_id and a.invocation_id == ^invocation_id
      )

    query = if attrs[:failed], do: where(query, [a], a.exit_code != 0 or a.status_code != 0), else: query

    case attrs[:mnemonic] do
      mnemonic when is_binary(mnemonic) and mnemonic != "" -> where(query, [a], a.mnemonic == ^mnemonic)
      _ -> query
    end
  end

  defp order(query, "queued_at", direction),
    do:
      order_by(query, [a], [
        {^direction(direction, :asc), fragment("coalesce(?, ?)", a.queued_at, a.worker_start_at)},
        asc: a.operation_id
      ])

  defp order(query, "completed_at", direction),
    do:
      order_by(query, [a], [
        {^direction(direction, :desc), fragment("coalesce(?, ?)", a.worker_completed_at, a.output_upload_completed_at)},
        asc: a.operation_id
      ])

  defp order(query, _duration, direction),
    do:
      order_by(query, [a], [
        {^direction(direction, :desc),
         fragment(
           "dateDiff('microsecond', coalesce(?, ?), coalesce(?, ?))",
           a.queued_at,
           a.worker_start_at,
           a.worker_completed_at,
           a.output_upload_completed_at
         )},
        asc: a.operation_id
      ])

  defp direction(direction, _default) when direction in ["asc", "desc"], do: String.to_existing_atom(direction)
  defp direction(_direction, default), do: default

  # `path:line[:column]: [fatal ]error: message` (Clang, GCC, Swift, javac),
  # Go's compiler, which only reports errors and omits the word, and rustc,
  # whose location follows its `error[E…]: message` line.
  @diagnostic ~r/\A(?<path>[^\s:][^:]*?):(?<line>\d+)(?::(?<column>\d+))?:\s*(?:fatal )?error:\s*(?<message>.+)\z/
  @go_diagnostic ~r/\A(?<path>[^\s:][^:]*?\.go):(?<line>\d+):(?<column>\d+):\s*(?<message>.+)\z/
  @rust_error ~r/\Aerror(?:\[[A-Z]\d+\])?:\s*(?<message>.+)\z/
  @rust_location ~r/\A\s*-->\s*(?<path>[^:]+):(?<line>\d+):(?<column>\d+)\z/
  @ansi ~r/\e\[[0-9;]*[A-Za-z]/

  @doc """
  The compiler errors in a failed action's recorded stderr, as
  `%{path, line, column, message}` in order. Empty when the action
  succeeded or its output has no recognised diagnostics.
  """
  def errors(%{exit_code: 0, status_code: 0}), do: []

  def errors(action) do
    action.stderr
    |> log_lines()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.flat_map(fn [line, next] -> List.wrap(diagnostic(line, next)) end)
    |> Enum.take(@max_errors)
  end

  @doc "Whether a recorded output line reports an error, for highlighting it."
  def error_line?(line) do
    line = String.replace(line, @ansi, "")
    Regex.match?(@diagnostic, line) or Regex.match?(@go_diagnostic, line) or Regex.match?(@rust_error, line)
  end

  @doc """
  Recorded output split into lines without terminal escape codes. A carriage
  return redraws its line in a terminal, so progress output keeps only the
  text written last, as CI logs show it.
  """
  def log_lines(""), do: []

  def log_lines(text) do
    text
    |> String.replace(@ansi, "")
    |> String.replace_suffix("\n", "")
    |> String.split(~r/\r?\n/)
    |> Enum.map(fn line -> line |> String.split("\r", trim: true) |> List.last("") end)
  end

  @doc """
  Presigned uploads for the streams in `records` longer than a record keeps:
  the whole stream, or its last 16 MiB, as `%{hash, size, offset, length, url}`. Records that
  `ingest/2` skips get none, and none are issued while the
  `:remote_action_log_copies_disabled` flag is on.
  """
  def log_uploads(%Project{} = project, records) when is_list(records) do
    if FeatureFlags.remote_action_log_copies_disabled?() do
      []
    else
      now = NaiveDateTime.utc_now()

      for record <- records,
          row(project, record, now),
          Regex.match?(@key_segment, record["invocation_id"]),
          stream <- @log_streams,
          hash = record[stream <> "_hash"],
          is_binary(hash) and Regex.match?(@hash, hash),
          size = integer(record[stream <> "_size"]),
          size > @max_log_bytes do
        length = min(size, @log_copy_bytes)
        key = log_key(project.account, project, record["invocation_id"], record["operation_id"], stream)

        %{
          hash: hash,
          size: size,
          offset: size - length,
          length: length,
          url: Storage.generate_upload_url(key, project.account, expires_in: @log_upload_seconds)
        }
      end
    end
  end

  def log_uploads(_project, _records), do: []

  defp log_key(%Account{name: account}, %Project{name: project}, invocation_id, operation_id, stream),
    do: "#{account}/#{project}/runs/#{invocation_id}/remote-actions/#{operation_id}/#{stream}.log"

  @doc """
  The copies of the action's truncated streams that object storage still
  holds: `%{"stdout" => end_of_stream | nil, "stderr" => ...}`.
  """
  def stored_logs(%Account{} = account, %Project{} = project, action) do
    Map.new(@log_streams, fn stream ->
      stored =
        if elem(stream(action, stream), 2) and Regex.match?(@key_segment, action.invocation_id) do
          account
          |> log_key(project, action.invocation_id, action.operation_id, stream)
          |> Storage.get_object_as_string(account)
        end

      {stream, stored}
    end)
  end

  @doc """
  What is recorded of one stream, in order, as `{offset, bytes}` ranges of
  the original stream: the record's preview, joined with the stored copy of
  the stream's end when they meet, or followed by it after a gap.
  """
  def recorded_log(action, stream, stored) when stream in @log_streams do
    {preview, size, _truncated} = stream(action, stream)

    case stored do
      tail when is_binary(tail) and byte_size(tail) <= size ->
        case size - byte_size(tail) do
          offset when offset <= byte_size(preview) -> [{0, binary_part(preview, 0, offset) <> tail}]
          offset -> [{0, preview}, {offset, tail}]
        end

      _ ->
        [{0, preview}]
    end
  end

  @doc """
  A stream's recorded text in `[offset, offset + limit)`, for the API, at
  most 64 KiB. `offset` defaults to the last `limit` bytes. Returns the
  recorded ranges too, so a reader asking for bytes in a gap learns where the
  recorded ones are.
  """
  def log_range(action, stream, stored, offset, limit) do
    ranges = recorded_log(action, stream, stored)
    {_preview, size, _truncated} = stream(action, stream)
    limit = limit |> Kernel.||(@max_log_range) |> min(@max_log_range) |> max(1)
    offset = offset || max(size - limit, 0)

    {start, text} =
      Enum.find_value(ranges, {offset, ""}, fn {start, bytes} ->
        stop = start + byte_size(bytes)

        if offset < stop and offset + limit > start do
          from = max(offset, start)
          {from, binary_part(bytes, from - start, min(offset + limit, stop) - from)}
        end
      end)

    %{
      stream: stream,
      size_bytes: size,
      offset: start,
      text: String.replace_invalid(text),
      recorded: Enum.map(ranges, fn {start, bytes} -> %{offset: start, length: byte_size(bytes)} end)
    }
  end

  @doc """
  The action's output as pages to show, stdout first, then stderr: each page
  is at most 64 KiB and 1000 lines of one stream, numbered across both, as
  `{:lines, first_number, text}`, with `{:gap, stream, omitted_bytes, reason}`
  where a stream's bytes are not there: `:skipped` between the preview and
  the stored end of a stream longer than a copy keeps, `:missing` after the
  preview when no copy is stored (not made yet, failed or expired). Pages hold slices of the stored text,
  so a long log is split into lines only one page at a time.
  """
  def log_pages(action, stored) do
    {pages, _number} =
      Enum.flat_map_reduce(@log_streams, 1, fn stream, number ->
        {_preview, size, _truncated} = stream(action, stream)

        {ranges, recorded_end} =
          action
          |> recorded_log(stream, Map.get(stored, stream))
          |> Enum.map_reduce(0, fn {start, bytes}, previous_end ->
            gap = if start > previous_end, do: [{:gap, stream, start - previous_end, :skipped}], else: []
            {{gap, String.replace_invalid(bytes)}, start + byte_size(bytes)}
          end)

        {pages, number} =
          Enum.flat_map_reduce(ranges, number, fn {gap, text}, number ->
            {pages, number} = page(text, number, [])
            {gap ++ pages, number}
          end)

        ending = if size > recorded_end, do: [{:gap, stream, size - recorded_end, :missing}], else: []
        {pages ++ ending, number}
      end)

    pages
  end

  defp page("", number, acc), do: {Enum.reverse(acc), number}

  defp page(text, number, acc) do
    window = binary_part(text, 0, min(byte_size(text), @log_page_bytes))
    newlines = :binary.matches(window, "\n")

    cut =
      cond do
        length(newlines) > @log_page_lines -> newlines |> Enum.at(@log_page_lines - 1) |> elem(0) |> Kernel.+(1)
        byte_size(text) <= @log_page_bytes -> byte_size(text)
        newlines != [] -> newlines |> List.last() |> elem(0) |> Kernel.+(1)
        true -> char_boundary(text, @log_page_bytes)
      end

    slice = binary_part(text, 0, cut)
    lines = length(:binary.matches(slice, "\n")) + if(String.ends_with?(slice, "\n"), do: 0, else: 1)
    page(binary_part(text, cut, byte_size(text) - cut), number + lines, [{:lines, number, slice} | acc])
  end

  # A line longer than a page is cut, but never inside a character.
  defp char_boundary(text, cut) do
    if cut <= @log_page_bytes - 3 or String.valid?(binary_part(text, 0, cut)),
      do: cut,
      else: char_boundary(text, cut - 1)
  end

  # A stream's preview, its original size (never less than the preview) and
  # whether the preview was cut short.
  defp stream(action, "stdout"),
    do: {action.stdout, max(action.stdout_size, byte_size(action.stdout)), action.stdout_truncated}

  defp stream(action, "stderr"),
    do: {action.stderr, max(action.stderr_size, byte_size(action.stderr)), action.stderr_truncated}

  defp diagnostic(line, next) do
    cond do
      match = Regex.named_captures(@diagnostic, line) -> issue(match)
      match = Regex.named_captures(@go_diagnostic, line) -> issue(match)
      match = rust_diagnostic(line, next) -> issue(match)
      true -> nil
    end
  end

  defp rust_diagnostic(line, next) do
    with %{} = error <- Regex.named_captures(@rust_error, line),
         %{} = location <- Regex.named_captures(@rust_location, next) do
      Map.merge(location, error)
    end
  end

  defp issue(match) do
    %{
      path: match["path"],
      line: String.to_integer(match["line"]),
      column: if(match["column"] in [nil, ""], do: nil, else: String.to_integer(match["column"])),
      message: String.trim(match["message"])
    }
  end

  @doc """
  An action's outcome: `:error` when the execution itself failed (a non-OK
  status, whatever the exit code), `:cached` for a cached result, `:passed`
  or `:failed` by the command's exit code.
  """
  def status(%{status_code: code}) when code != 0, do: :error
  def status(%{exit_code: 0, cached_result: true}), do: :cached
  def status(%{exit_code: 0}), do: :passed
  def status(_action), do: :failed

  @doc "One remote action of an invocation, with its command and output."
  def get(project_id, invocation_id, operation_id) do
    with true <- is_binary(operation_id) and Regex.match?(@uuid, operation_id),
         %Action{} = action <-
           ClickHouseRepo.one(
             from(a in Action,
               hints: ["FINAL"],
               where:
                 a.project_id == ^project_id and a.invocation_id == ^invocation_id and
                   a.operation_id == ^operation_id,
               limit: 1
             )
           ) do
      {:ok, action |> Map.from_struct() |> Map.delete(:__meta__) |> with_phases()}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The operation IDs whose declared outputs include each of `outputs`, for
  linking profile actions to their records. An output with records of more
  than one action digest maps to several IDs; callers link only unique ones.
  """
  def by_output(_project_id, _invocation_id, []), do: %{}

  def by_output(project_id, invocation_id, outputs) do
    from(a in Action,
      hints: ["FINAL"],
      where: a.project_id == ^project_id and a.invocation_id == ^invocation_id,
      where: fragment("hasAny(?, ?)", a.output_paths, type(^outputs, {:array, :string})),
      select: {a.operation_id, a.action_hash, a.output_paths}
    )
    |> ClickHouseRepo.all()
    |> Enum.flat_map(fn {id, hash, paths} ->
      for path <- paths, path in outputs, do: {path, {hash, id}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The API shape of a listed action, as returned by `list/3`."
  def summary_json(action) do
    %{
      id: action.operation_id,
      invocation_id: action.invocation_id,
      action_digest: %{hash: action.action_hash, size_bytes: action.action_size},
      mnemonic: action.mnemonic,
      target: action.target,
      execution_path: action.execution_path,
      memory_gb: action.memory_gb,
      cached_result: action.cached_result,
      status_code: action.status_code,
      exit_code: action.exit_code,
      queued_at: iso8601(action.queued_at || action.worker_start_at),
      duration_ms: action.duration_ms,
      queue_ms: action.queue_ms,
      input_fetch_ms: action.input_fetch_ms,
      execution_ms: action.execution_ms,
      output_upload_ms: action.output_upload_ms
    }
  end

  @doc "The API shape of one action from `get/3`, with its command and output."
  def json(action) do
    action
    |> summary_json()
    |> Map.merge(%{
      tool_name: action.tool_name,
      tool_version: action.tool_version,
      configuration_id: action.configuration_id,
      worker: action.worker,
      sandbox_id: action.sandbox_id,
      timeout_ms: action.timeout_ms,
      do_not_cache: action.do_not_cache,
      arguments: action.arguments,
      arguments_truncated: action.arguments_truncated,
      environment: pairs_json(action.environment_names, action.environment_values),
      working_directory: action.working_directory,
      platform: pairs_json(action.platform_names, action.platform_values),
      output_paths: action.output_paths,
      output_count: action.output_count,
      status_message: action.status_message,
      stdout: action.stdout,
      stdout_size_bytes: action.stdout_size,
      stdout_truncated: action.stdout_truncated,
      stderr: action.stderr,
      stderr_size_bytes: action.stderr_size,
      stderr_truncated: action.stderr_truncated,
      timestamps:
        Map.new(@timestamp_names, fn name -> {name, iso8601(Map.get(action, String.to_existing_atom(name <> "_at")))} end),
      errors: errors(action)
    })
  end

  defp pairs_json(names, values), do: Enum.zip_with(names, values, &%{name: &1, value: &2})

  defp iso8601(nil), do: nil
  defp iso8601(%NaiveDateTime{} = value), do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp with_phases(action) do
    phases =
      Map.new(@phases, fn {phase, start, finish} -> {phase, milliseconds(action[start], action[finish])} end)

    started = action.queued_at || action.worker_start_at
    finished = action.worker_completed_at || action.output_upload_completed_at

    action
    |> Map.merge(phases)
    |> Map.put(:duration_ms, milliseconds(started, finished))
  end

  defp milliseconds(%NaiveDateTime{} = start, %NaiveDateTime{} = finish) do
    duration = NaiveDateTime.diff(finish, start, :microsecond) / 1000
    if duration >= 0, do: duration
  end

  defp milliseconds(_start, _finish), do: nil

  # The VM size the scheduler gives an action of this memory; nil when the
  # record has no size the scheduler offers.
  defp vcpus(memory_gb) do
    if memory_gb in Settings.memory_sizes_gb(), do: Settings.shape(memory_gb).vcpus
  end

  @doc "The recorded arguments as one shell command line, to copy."
  def command_line(action), do: Enum.map_join(action.arguments, " ", &quote_shell/1)

  defp quote_shell(value) do
    if Regex.match?(~r/\A[A-Za-z0-9_\-.,\/:=+@%]+\z/, value),
      do: value,
      else: "'" <> String.replace(value, "'", ~S('\'')) <> "'"
  end
end
