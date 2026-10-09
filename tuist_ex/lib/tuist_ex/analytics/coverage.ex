defmodule TuistEx.Analytics.Coverage do
  @moduledoc false

  # The line coverage of a `mix test --cover` run, read from Erlang's `cover`
  # and shaped as the server's `coverage` block: one entry per source file of
  # the repository, with the OTP application it belongs to, whether it is test
  # code, and how many times each executable line ran.
  #
  # The counters are read by the formatter when the suite finishes: every test
  # has run, and Mix's own coverage tool has not yet turned them into its
  # report, nor, in an umbrella, restarted `cover` for the next application.

  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Git
  alias TuistEx.HTTP, as: Client

  # What picks tests other than the whole suite. `--include` only adds tests
  # the configuration excluded, and a shard's files are known to the server
  # from the shard plan, so neither makes a run partial.
  @filters ~w(--only --exclude --failed --stale --name-pattern --max-failures)
  # The `mix test` options that take a value, which is not a test file.
  @value_switches ~w(--only --exclude --include --seed --timeout --max-cases --max-failures
                     --max-requires --partitions --formatter --slowest --slowest-modules
                     --name-pattern --export-coverage --exit-status --repeat-until-failure)

  def requested?(test_args), do: "--cover" in test_args

  @doc """
  Whether the run's own arguments left tests out on purpose: a filter, or
  explicit test files or lines.
  """
  def partial?(test_args), do: files?(test_args) or option?(test_args, @filters)

  @doc "Whether the arguments give one of `options`, as `--option` or `--option=value`."
  def option?(test_args, options) do
    Enum.any?(test_args, fn arg ->
      Enum.any?(options, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
    end)
  end

  @doc "The test files or lines the arguments name."
  def files([switch, _value | rest]) when switch in @value_switches, do: files(rest)
  def files(["-" <> _ | rest]), do: files(rest)
  def files([file | rest]), do: [file | files(rest)]
  def files([]), do: []

  def files?(test_args), do: files(test_args) != []

  @doc """
  The counters `cover` holds, one entry per source file with its lines and
  its functions, or nil when it is not running. Called in the project the
  suite belongs to, an umbrella's application for its own suite: its test
  paths say what is test code, and its directory finds sources a build
  compiled elsewhere.
  """
  def snapshot(project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    if Process.whereis(:cover_server) do
      {:result, entries, _failures} = :cover.analyse(:calls, :line)
      calls = function_calls()
      test_dirs = Enum.map(config[:test_paths] || ["test"], &Path.expand(&1, project_dir))
      default_app = config[:app] && to_string(config[:app])
      ignored = get_in(config, [:test_coverage, :ignore_modules]) || []

      entries
      |> Enum.reject(fn {{_module, line}, _count} -> line == 0 end)
      |> Enum.group_by(fn {{module, _line}, _count} -> module end, fn {{_module, line}, count} ->
        {line, count}
      end)
      |> Enum.map(fn {module, lines} -> {original(module), lines} end)
      |> Enum.reject(fn {module, _lines} -> ignored?(module, ignored) end)
      |> Enum.flat_map(fn {module, lines} ->
        {source, clauses} = build_info(module)

        case locate(source, project_dir) do
          nil ->
            []

          path ->
            [
              {path, application(module) || default_app, lines,
               Enum.map(clauses, fn {head, body, function} -> {head, body, {module, function}} end)}
            ]
        end
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {path, modules} ->
        # Several modules can share a file, and a line attributed to more
        # than one keeps its highest count, as excoveralls does. A module
        # Mimic copied is one of them: the counters from before the copy stay
        # under its own name, the later ones under its original's.
        lines =
          Enum.reduce(modules, %{}, fn {_path, _app, lines, _clauses}, acc ->
            Enum.reduce(lines, acc, fn {line, count}, acc ->
              Map.update(acc, line, count, &max(&1, count))
            end)
          end)

        %{
          path: path,
          app: modules |> hd() |> elem(1),
          test?: Enum.any?(test_dirs, &String.starts_with?(path, &1 <> "/")),
          lines: lines,
          functions: functions(Enum.flat_map(modules, &elem(&1, 3)), lines, calls)
        }
      end)
    end
  end

  # The modules the project's coverage configuration leaves out, as Mix's
  # coverage tool reads `ignore_modules`: a module, or a pattern its name
  # matches.
  defp ignored?(module, ignored) do
    Enum.any?(ignored, fn
      %Regex{} = pattern -> Regex.match?(pattern, inspect(module))
      other -> other == module
    end)
  end

  # Mimic, the mocking library most suites use, swaps a copied module for a
  # proxy and keeps the original's code under another name, cover-compiled
  # from its binary, so the counters a test moves in it are the original
  # module's lines.
  @mimic_original ".Mimic.Original.Module"

  defp original(module) do
    name = Atom.to_string(module)

    if String.ends_with?(name, @mimic_original),
      do: name |> String.replace_suffix(@mimic_original, "") |> String.to_atom(),
      else: module
  end

  # How many times each function was called, keyed by the module it belongs
  # to once Mimic's copies are mapped back to their originals.
  defp function_calls do
    {:result, entries, _failures} = :cover.analyse(:calls, :function)

    Map.new(entries, fn {{module, name, arity}, count} ->
      {{original(module), name, arity}, count}
    end)
  end

  # The module's source and the line each of its function clauses starts at,
  # read off its build: a module cover-compiled from a binary, as Mimic's
  # copies are, names no source of its own.
  defp build_info(module) do
    with path when is_list(path) <- :code.where_is_file(~c"#{module}.beam"),
         {:ok, {_module, chunks}} <-
           :beam_lib.chunks(path, [:compile_info, :abstract_code], [:allow_missing_chunks]) do
      source =
        case chunks[:compile_info] do
          info when is_list(info) -> if source = info[:source], do: to_string(source)
          _ -> nil
        end

      {source, clause_starts(chunks[:abstract_code])}
    else
      _ -> {nil, []}
    end
  end

  # Each clause's head line, which is where its function is said to start,
  # and the line of its first expression, which runs once per call that
  # takes the clause.
  defp clause_starts({:raw_abstract_v1, forms}) do
    for {:function, _anno, name, arity, clauses} <- forms,
        {:clause, anno, _args, _guards, [first | _]} <- clauses,
        line = :erl_anno.line(anno),
        line > 0,
        do: {line, :erl_anno.line(elem(first, 1)), {name, arity}}
  end

  defp clause_starts(_abstract_code), do: []

  # Each executable line belongs to the function whose clause body starts
  # closest above it, including the anonymous functions inside it, whichever
  # of the file's modules it is in. Functions the compiler generates
  # (`__info__/1`, `__struct__/0`, `module_info/0`) are not listed, but still
  # end the function before them. A function's executions are the runs of its
  # clauses' first expressions, as cover counts calls, or cover's own count
  # when that is higher: the calls a module Mimic copied took before the copy
  # are only in its lines.
  defp functions(clauses, lines, calls) do
    clauses = Enum.uniq(clauses)

    starts =
      clauses |> Enum.map(fn {_head, body, function} -> {body, function} end) |> Enum.sort()

    head_lines =
      clauses
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {head, _body, function}, acc -> Map.put_new(acc, function, head) end)

    # A line two functions' clauses start on, as a default argument's does,
    # counts both, so it says nothing about either.
    shared =
      clauses
      |> Enum.group_by(fn {_head, body, _function} -> body end, fn {_head, _body, function} ->
        function
      end)
      |> Enum.filter(fn {_body, functions} -> functions |> Enum.uniq() |> length() > 1 end)
      |> MapSet.new(fn {body, _functions} -> body end)

    clause_calls =
      Enum.reduce(clauses, %{}, fn {_head, body, function}, acc ->
        count = if MapSet.member?(shared, body), do: 0, else: Map.get(lines, body, 0)
        Map.update(acc, function, count, &(&1 + count))
      end)

    lines
    |> Enum.sort()
    |> Enum.reduce({starts, nil, %{}}, fn {line, count}, {starts, owner, acc} ->
      {starts, owner} = advance(starts, owner, line)
      acc = if owner, do: Map.update(acc, owner, [count], &[count | &1]), else: acc
      {starts, owner, acc}
    end)
    |> elem(2)
    |> Enum.reject(fn {{_module, {name, _arity}}, _counts} -> generated?(name) end)
    |> Enum.map(fn {{module, {name, arity}} = function, counts} ->
      %{
        name: "#{name}/#{arity}",
        line: Map.fetch!(head_lines, function),
        calls: max(Map.get(calls, {module, name, arity}, 0), Map.fetch!(clause_calls, function)),
        covered: Enum.count(counts, &(&1 > 0)),
        executable: length(counts)
      }
    end)
    |> Enum.sort_by(&{&1.line, &1.name})
  end

  defp advance([{start, function} | rest], _owner, line) when start <= line,
    do: advance(rest, function, line)

  defp advance(starts, owner, _line), do: {starts, owner}

  defp generated?(name),
    do: name == :module_info or String.starts_with?(Atom.to_string(name), "__")

  defp application(module) do
    case :application.get_application(module) do
      {:ok, app} -> to_string(app)
      :undefined -> nil
    end
  end

  # A build compiled on another machine, such as a shard's, names its sources
  # by that machine's paths. Its files are found here by the longest suffix
  # that exists under the project.
  defp locate(nil, _project_dir), do: nil

  defp locate(path, project_dir) do
    if File.regular?(path) do
      path
    else
      parts = Path.split(path)

      Enum.find_value(1..max(length(parts) - 1, 1)//1, fn drop ->
        candidate = Path.join([project_dir | Enum.drop(parts, drop)])
        if File.regular?(candidate), do: candidate
      end)
    end
  end

  @doc """
  The `coverage` block for the files a snapshot holds that live in the
  repository at `root`, keyed by their path relative to it, with the blob each
  had in the checkout. Test code keeps its counts but not its lines: the
  server leaves it out of every figure.
  """
  def report(snapshot, root, blob_ids, partial?) do
    files =
      for %{path: path} = file <- snapshot, relative = relative(path, root), relative != nil do
        {line_numbers, execution_counts} =
          file.lines |> Enum.sort() |> Enum.unzip()

        covered = Enum.count(execution_counts, &(&1 > 0))

        %{
          path: relative,
          git_blob_id: Map.get(blob_ids, relative),
          targets: List.wrap(file.app),
          is_test: file.test?,
          covered_lines: covered,
          executable_lines: length(line_numbers),
          line_numbers: if(file.test?, do: [], else: line_numbers),
          execution_counts: if(file.test?, do: [], else: execution_counts),
          functions:
            if(file.test?, do: [], else: Enum.map(Map.get(file, :functions, []), &function_row/1))
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
      end

    %{
      tool: "cover",
      tool_version: "OTP #{Env.otp_version()}/Elixir #{Env.elixir_version()}",
      partial: partial?,
      files: Enum.sort_by(files, & &1.path)
    }
  end

  defp function_row(function) do
    %{
      name: function.name,
      line_number: function.line,
      execution_count: function.calls,
      covered_lines: function.covered,
      executable_lines: function.executable
    }
  end

  defp relative(path, root) do
    if String.starts_with?(path, root <> "/"), do: Path.relative_to(path, root)
  end

  @doc """
  Builds a run's block from the snapshots its formatter took. Reads the
  repository's root and blobs from the checkout at `dir`.
  """
  def build(snapshot, dir, partial?) do
    with {:ok, root} <- Git.toplevel(dir) do
      root = Path.expand(root)
      covered = MapSet.new(snapshot, &relative(&1.path, root))

      blob_ids =
        case Git.blob_ids(root, &MapSet.member?(covered, &1)) do
          {:ok, blob_ids} -> blob_ids
          :error -> %{}
        end

      {:ok, report(snapshot, root, blob_ids, partial?)}
    end
  end

  @doc """
  Puts the block into the run's payload: inline when it compresses to no more
  than the server's threshold, and otherwise uploaded first, the run naming
  the upload's key.
  """
  def attach(payload, coverage, options) do
    compressed = deflate(Enum.map_join(coverage.files, "\n", &JSON.encode!/1))

    if byte_size(compressed) <= inline_threshold(options) do
      {:ok, Map.put(payload, :coverage, coverage)}
    else
      with {:ok, %{"storage_key" => key, "upload_url" => url}} <-
             HTTP.project_request(
               :post,
               "/tests/coverage/uploads",
               %{test_run_id: payload.id},
               options
             ),
           {:ok, _etag} <- Client.put_binary(url, compressed) do
        {:ok,
         Map.put(payload, :coverage, coverage |> Map.delete(:files) |> Map.put(:storage_key, key))}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_response, other}}
      end
    end
  end

  defp inline_threshold(options) do
    case HTTP.project_request(:get, "/tests/coverage/settings", nil, options) do
      {:ok, %{"inline_threshold_bytes" => bytes}} when is_integer(bytes) -> bytes
      _ -> 5_000_000
    end
  end

  # Raw DEFLATE, what the server inflates (`PublishCoverageWorker`).
  defp deflate(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    compressed = IO.iodata_to_binary(:zlib.deflate(z, data, :finish))
    :zlib.deflateEnd(z)
    :zlib.close(z)
    compressed
  end
end
