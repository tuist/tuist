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
  def partial?(test_args) do
    files?(test_args) or
      Enum.any?(test_args, fn arg ->
        Enum.any?(@filters, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
      end)
  end

  defp files?([switch, _value | rest]) when switch in @value_switches, do: files?(rest)
  defp files?(["-" <> _ | rest]), do: files?(rest)
  defp files?([_file | _rest]), do: true
  defp files?([]), do: false

  @doc """
  The counters `cover` holds, one entry per source file, or nil when it is
  not running. Called in the project the suite belongs to, an umbrella's
  application for its own suite: its test paths say what is test code, and
  its directory finds sources a build compiled elsewhere.
  """
  def snapshot(project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    if Process.whereis(:cover_server) do
      {:result, entries, _failures} = :cover.analyse(:calls, :line)
      test_dirs = Enum.map(config[:test_paths] || ["test"], &Path.expand(&1, project_dir))
      default_app = config[:app] && to_string(config[:app])
      ignored = get_in(config, [:test_coverage, :ignore_modules]) || []

      entries
      |> Enum.reject(fn {{_module, line}, _count} -> line == 0 end)
      |> Enum.group_by(fn {{module, _line}, _count} -> module end, fn {{_module, line}, count} ->
        {line, count}
      end)
      |> Enum.reject(fn {module, _lines} -> ignored?(module, ignored) end)
      |> Enum.flat_map(fn {module, lines} ->
        case locate(source(module), project_dir) do
          nil -> []
          path -> [{path, application(module) || default_app, lines}]
        end
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {path, modules} ->
        %{
          path: path,
          app: modules |> hd() |> elem(1),
          test?: Enum.any?(test_dirs, &String.starts_with?(path, &1 <> "/")),
          # Several modules can share a file, and a line attributed to more
          # than one keeps its highest count, as excoveralls does.
          lines:
            Enum.reduce(modules, %{}, fn {_path, _app, lines}, acc ->
              Enum.reduce(lines, acc, fn {line, count}, acc ->
                Map.update(acc, line, count, &max(&1, count))
              end)
            end)
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

  defp source(module) do
    case module.module_info(:compile)[:source] do
      nil -> nil
      source -> to_string(source)
    end
  rescue
    _ -> nil
  end

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
          functions: []
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
