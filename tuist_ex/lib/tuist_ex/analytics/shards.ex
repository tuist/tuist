defmodule TuistEx.Analytics.Shards do
  @moduledoc false

  # Test sharding: splitting a suite across machines so each one runs a share
  # of it, balanced by how long the tests took before.
  #
  # The unit Tuist plans with is the ExUnit module, because that is what test
  # runs report timings for. The unit Mix can run is the test file, so modules
  # are mapped back to the files defining them.
  #
  # A plan can also carry the compiled build (`_build/test`), so that only one
  # machine compiles and every shard downloads the result, the equivalent of
  # building for testing once and testing without building.

  alias TuistEx.Analytics.HTTP
  alias TuistEx.HTTP, as: RawHTTP

  # Storage accepts parts of at least 5 MiB, except for the last one.
  @part_bytes 64 * 1024 * 1024

  @doc """
  The name every machine of one pipeline run agrees on. Set explicitly, or
  derived from the continuous integration provider's run identifier.
  """
  def reference(options, environment \\ &System.get_env/1) do
    cond do
      value = present(Keyword.get(options, :shard_reference)) ->
        {:ok, value}

      value = present(environment.("TUIST_SHARD_REFERENCE")) ->
        {:ok, value}

      run = present(environment.("GITHUB_RUN_ID")) ->
        {:ok, "github-#{run}-#{environment.("GITHUB_RUN_ATTEMPT") || "1"}"}

      value = present(environment.("CIRCLE_WORKFLOW_ID")) ->
        {:ok, "circleci-#{value}"}

      value = present(environment.("BUILDKITE_BUILD_ID")) ->
        {:ok, "buildkite-#{value}"}

      value = present(environment.("CI_PIPELINE_ID")) ->
        {:ok, "gitlab-#{value}"}

      true ->
        {:error,
         "Could not derive a shard reference. Set TUIST_SHARD_REFERENCE or pass --shard-reference."}
    end
  end

  @doc """
  The shard this machine runs, from `--shard-index` or `TUIST_SHARD_INDEX`,
  or `nil` when the run is not sharded.
  """
  def index(options, environment \\ &System.get_env/1) do
    case Keyword.get(options, :shard_index) || environment.("TUIST_SHARD_INDEX") do
      index when is_integer(index) and index >= 0 ->
        index

      index when is_binary(index) ->
        case Integer.parse(index) do
          {index, ""} when index >= 0 -> index
          _ -> Mix.raise("TUIST_SHARD_INDEX expects a shard number, got: #{index}")
        end

      _ ->
        nil
    end
  end

  @doc """
  Maps every test file of the project to the unit it is planned as, read
  without loading the files.

  A file runs as a whole, so it is planned as one unit: the first, by name,
  of the modules it defines, which is the name its timings are reported
  under. A file that defines no module the parser can see (they are generated
  by a macro, say) is planned under its own path. A file that cannot be read
  or parsed stops the plan: leaving it out would let every shard pass while
  the suite itself cannot compile.
  """
  def test_units(test_paths \\ test_paths()) do
    for path <- test_paths,
        file <- Path.wildcard(Path.join(path, "**/*_test.exs")),
        into: %{},
        do: {unit(file), file}
  end

  defp test_paths, do: Mix.Project.config()[:test_paths] || ["test"]

  defp unit(file) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source) do
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _meta, [{:__aliases__, _, parts} | _]} = node, acc when is_list(parts) ->
            if Enum.all?(parts, &is_atom/1),
              do: {node, [Enum.join(parts, ".") | acc]},
              else: {node, acc}

          node, acc ->
            {node, acc}
        end)

      Enum.min(modules, fn -> file end)
    else
      _ -> Mix.raise("Cannot plan the shards: #{file} could not be read or parsed.")
    end
  end

  @doc """
  The test files a shard runs, given the units it was assigned.
  """
  def files(assigned, units) do
    assigned
    |> Enum.map(&Map.get(units, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Narrows a shard's files to the test paths given on the command line, and
  takes those paths out of the arguments: Mix runs the union of the paths it
  is given, so leaving them in would run them on every shard.

  Returns `{arguments, files}`. A path with a line (`test/a_test.exs:12`)
  stays as given when its file belongs to the shard.
  """
  def restrict(test_args, files) do
    {selectors, args} =
      Enum.split_with(test_args, fn arg ->
        not String.starts_with?(arg, "-") and File.exists?(selector_path(arg))
      end)

    if selectors == [] do
      {args, files}
    else
      selected =
        Enum.flat_map(files, fn file ->
          lines =
            Enum.filter(
              selectors,
              &(&1 != selector_path(&1) and same_path?(selector_path(&1), file))
            )

          whole? = Enum.any?(selectors, &(&1 == selector_path(&1) and within?(file, &1)))

          cond do
            whole? -> [file]
            lines != [] -> lines
            true -> []
          end
        end)

      {args, selected}
    end
  end

  defp selector_path(arg), do: arg |> String.split(":") |> hd()
  defp same_path?(a, b), do: Path.expand(a) == Path.expand(b)

  defp within?(file, path) do
    file = Path.expand(file)
    path = Path.expand(path)
    file == path or String.starts_with?(file, path <> "/")
  end

  @doc """
  Asks the server to split `modules` into shards. Returns the plan: its
  `"shard_count"` and, per shard, its `"index"`, `"test_targets"` and
  `"estimated_duration_ms"`.
  """
  def create_plan(reference, modules, options) do
    body =
      %{
        reference: reference,
        modules: Enum.sort(modules),
        granularity: "module",
        shard_min: Keyword.get(options, :shard_min),
        shard_max: Keyword.get(options, :shard_max),
        shard_total: Keyword.get(options, :shard_total),
        shard_max_duration: Keyword.get(options, :shard_max_duration),
        git_branch: TuistEx.Analytics.Env.git_branch()
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    HTTP.project_request(:post, "/tests/shards", body, options)
  end

  @doc """
  Looks up what one shard runs: its `"modules"`, the plan's id, and where to
  download the build from when one was uploaded.
  """
  def fetch(reference, index, options) do
    HTTP.project_request(
      :get,
      "/tests/shards/#{URI.encode(reference, &URI.char_unreserved?/1)}/#{index}",
      nil,
      options
    )
  end

  @doc """
  Archives the build directory and uploads it for the plan's shards.
  """
  def upload_build(reference, build_path, options) do
    archive =
      Path.join(System.tmp_dir!(), "tuist-ex-build-#{System.unique_integer([:positive])}.tar.gz")

    try do
      with :ok <- archive(build_path, archive),
           {:ok, %{"data" => %{"upload_id" => upload_id}}} <-
             HTTP.project_request(
               :post,
               "/tests/shards/upload/start",
               %{reference: reference},
               options
             ),
           {:ok, parts} <- upload_parts(archive, reference, upload_id, options),
           {:ok, _} <-
             HTTP.project_request(
               :post,
               "/tests/shards/upload/complete",
               %{reference: reference, upload_id: upload_id, parts: parts},
               options
             ) do
        {:ok, File.stat!(archive).size}
      end
    after
      File.rm(archive)
    end
  end

  defp upload_parts(archive, reference, upload_id, options) do
    archive
    |> File.stream!(@part_bytes)
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {chunk, part_number}, {:ok, parts} ->
      with {:ok, %{"data" => %{"url" => url}}} <-
             HTTP.project_request(
               :post,
               "/tests/shards/upload/generate-url",
               %{reference: reference, upload_id: upload_id, part_number: part_number},
               options
             ),
           {:ok, etag} <- RawHTTP.put_binary(url, chunk) do
        {:cont, {:ok, parts ++ [%{part_number: part_number, etag: etag}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Downloads a plan's build into the build directory. `{:error, :no_build}`
  means the plan has none, which is fine: the shard compiles as usual.
  """
  def download_build(url, build_path) when is_binary(url) do
    archive =
      Path.join(System.tmp_dir!(), "tuist-ex-build-#{System.unique_integer([:positive])}.tar.gz")

    try do
      case RawHTTP.download(url, archive) do
        :ok ->
          File.mkdir_p!(build_path)
          extract(archive, build_path)

        {:error, {:http, status}} when status in [403, 404] ->
          {:error, :no_build}

        {:error, reason} ->
          {:error, reason}
      end
    after
      File.rm(archive)
    end
  end

  def download_build(_url, _build_path), do: {:error, :no_build}

  @links ".tuist-links"

  # A build links out of itself: a dependency's `priv` directory points into
  # `deps/`, and the project's own into the checkout. The archive tool
  # refuses to extract links that leave the directory, so they travel as a
  # list instead and are recreated after extraction.
  @doc false
  def archive(build_path, archive) do
    {files, links} = walk(build_path, "")

    entries =
      [{String.to_charlist(@links), :erlang.term_to_binary(links)}] ++
        Enum.map(files, &{String.to_charlist(&1), String.to_charlist(Path.join(build_path, &1))})

    :erl_tar.create(String.to_charlist(archive), entries, [:compressed])
  end

  defp walk(root, relative) do
    root
    |> Path.join(relative)
    |> File.ls!()
    |> Enum.reduce({[], []}, fn entry, {files, links} ->
      path = Path.join(relative, entry)

      case File.lstat!(Path.join(root, path)) do
        %File.Stat{type: :symlink} ->
          {files, [{path, File.read_link!(Path.join(root, path))} | links]}

        %File.Stat{type: :directory} ->
          {inner_files, inner_links} = walk(root, path)
          {inner_files ++ files, inner_links ++ links}

        %File.Stat{type: :regular} ->
          {[path | files], links}

        _other ->
          {files, links}
      end
    end)
  end

  # The build is unpacked next to the build directory and takes its place
  # only once complete, so nothing is written through whatever the existing
  # directory links to, and a failed download leaves it as it was.
  @doc false
  def extract(archive, build_path) do
    staging = build_path <> ".tuist-download"
    File.rm_rf!(staging)
    File.mkdir_p!(staging)

    with :ok <-
           :erl_tar.extract(String.to_charlist(archive), [
             :compressed,
             {:cwd, String.to_charlist(staging)}
           ]),
         {:ok, links} <- read_links(Path.join(staging, @links)) do
      File.rm(Path.join(staging, @links))
      Enum.each(links, &link(staging, build_path, &1))
      File.rm_rf!(build_path)
      File.rename!(staging, build_path)
      :ok
    else
      error ->
        File.rm_rf!(staging)
        error
    end
  end

  defp read_links(manifest) do
    with {:ok, binary} <- File.read(manifest),
         links when is_list(links) <- :erlang.binary_to_term(binary, [:safe]),
         true <-
           Enum.all?(
             links,
             &match?({path, target} when is_binary(path) and is_binary(target), &1)
           ) do
      {:ok, links}
    else
      _ -> {:error, :invalid_link_manifest}
    end
  rescue
    _ -> {:error, :invalid_link_manifest}
  end

  # The list comes from the archive. A link is recreated only when it sits
  # inside the build, below real directories all the way (a link recreated a
  # moment ago could otherwise redirect the next one), and points inside the
  # checkout once the build is in place. Nothing is ever removed to make room.
  defp link(staging, build_path, {path, target}) do
    segments = Path.split(path)
    checkout = Path.expand(File.cwd!())
    resolved = Path.expand(target, Path.dirname(Path.join(build_path, path)))

    inside_build? = Path.type(path) == :relative and ".." not in segments
    inside_checkout? = resolved == checkout or String.starts_with?(resolved, checkout <> "/")

    if inside_build? and inside_checkout? and real_directories?(staging, Enum.drop(segments, -1)) and
         match?({:error, :enoent}, File.lstat(Path.join(staging, path))) do
      File.mkdir_p!(Path.dirname(Path.join(staging, path)))
      File.ln_s!(target, Path.join(staging, path))
    end

    :ok
  end

  defp real_directories?(_root, []), do: true

  defp real_directories?(root, [segment | rest]) do
    path = Path.join(root, segment)

    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> real_directories?(path, rest)
      {:error, :enoent} -> true
      _ -> false
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil
end
