defmodule TuistEx.Analytics.Enumeration do
  @moduledoc false

  # The tests a run could have executed, whatever its filters picked: the
  # Mix counterpart of `xcodebuild -enumerate-tests`, which the server keeps
  # to tell which candidates a selective run skipped.
  #
  # ExUnit reports a test that `--only`, `--exclude` or `--name-pattern`
  # leaves out to the formatters as `{:excluded, _}`, so the formatter's list
  # is complete for those. Other options keep tests from being reported at
  # all: `--stale` and explicit files or lines load only some files,
  # `--failed` drops the tests that passed before they reach the filters, and
  # `--max-failures` stops before the rest. For those, the tests the run never
  # reported are read in this process after the run, from each test module's
  # `__ex_unit__/0`, requiring the test files that were not loaded.
  #
  # The alternative was a second `mix test --only <a tag no test has>`, which
  # reports every test as excluded through the same formatter. It boots
  # another VM, compiles every test file and runs `test_helper.exs` again,
  # which in most projects starts the application and its database, and it
  # still could not see what `--failed` drops. `__ex_unit__/0` is what
  # `ExUnit.Runner` itself reads, and `ExUnit.TestModule` and `ExUnit.Test`
  # are public structs. Requiring after the run is accepted: `ExUnit.Server`
  # takes modules again once a suite finished, and nothing runs them.

  alias TuistEx.Analytics.Coverage
  alias TuistEx.Analytics.ExUnitFormatter

  # Options whose tests ExUnit never reports to the formatters.
  @unreported ~w(--stale --failed --max-failures)

  @doc """
  Whether the run's own arguments keep tests from being reported, so the
  formatter's list is not the suite. The files a shard appends are not
  counted: each shard lists its share and the server unions them.
  """
  def load?(test_args) do
    Coverage.files?(test_args) or
      Enum.any?(test_args, fn arg ->
        Enum.any?(@unreported, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
      end)
  end

  @doc """
  What reading the suite needs to know about the project the suite belongs
  to, an umbrella's application for its own suite: its test files, found as
  `mix test` finds them, and the options it compiles them with.
  """
  def project(config \\ Mix.Project.config(), project_dir \\ File.cwd!()) do
    test_paths =
      config[:test_paths] || if(File.dir?(Path.join(project_dir, "test")), do: ["test"], else: [])

    # Elixir 1.19 matches every file and loads those `:test_load_filters`
    # picks; before it, `:test_pattern` alone said what a test file is.
    {pattern, load_filters} =
      if Version.match?(System.version(), ">= 1.19.0") do
        {config[:test_pattern] || "*.{ex,exs}",
         config[:test_load_filters] || [&String.ends_with?(&1, "_test.exs")]}
      else
        {config[:test_pattern] || "*_test.exs", [fn _file -> true end]}
      end

    # The filters see the paths as `mix test` does, relative to the project.
    files =
      test_paths
      |> Enum.flat_map(fn path ->
        files = Path.wildcard(Path.join([Path.expand(path, project_dir), "**", pattern]))

        if Path.type(path) == :absolute,
          do: files,
          else: Enum.map(files, &Path.relative_to(&1, project_dir))
      end)
      |> Enum.uniq()
      |> Enum.filter(&matches?(&1, load_filters))
      |> Enum.map(&Path.expand(&1, project_dir))

    %{files: files, elixirc_options: config[:test_elixirc_options] || []}
  end

  defp matches?(file, filters) do
    Enum.any?(filters, fn
      filter when is_binary(filter) -> file == filter
      %Regex{} = filter -> Regex.match?(filter, file)
      filter when is_function(filter, 1) -> filter.(file)
      _ -> false
    end)
  end

  @doc """
  The suite's tests: the ones the formatter saw and, when `load?`, every
  test of the project's test files, requiring those the run did not load.
  """
  def complete(reported, project, load?)

  def complete(reported, _project, false), do: Enum.uniq(reported)

  def complete(reported, %{files: files, elixirc_options: elixirc_options}, true) do
    files = MapSet.new(files)
    loaded = MapSet.new(test_modules(), & &1.file)

    missing = files |> Enum.reject(&MapSet.member?(loaded, &1)) |> Enum.sort()
    if missing != [], do: require_files(missing, elixirc_options)

    modules = Enum.filter(test_modules(), &MapSet.member?(files, &1.file))
    Enum.uniq(reported ++ tests_of(modules))
  end

  @doc """
  The identities of the tests of `test_modules`, as the formatter names the
  tests it reports.
  """
  def tests_of(test_modules) do
    for %ExUnit.TestModule{tests: tests} <- test_modules,
        %ExUnit.Test{} = test <- tests,
        uniq: true,
        do: ExUnitFormatter.identity(test)
  end

  defp test_modules do
    for {module, _} <- :code.all_loaded(),
        function_exported?(module, :__ex_unit__, 0),
        match?(%ExUnit.TestModule{}, test_module = module.__ex_unit__()),
        do: test_module
  end

  # With the options `mix test` compiles test files with: without
  # `infer_signatures: false`, a large suite takes much longer.
  defp require_files(files, elixirc_options) do
    options =
      Keyword.take(
        Keyword.merge([docs: false, debug_info: false, infer_signatures: false], elixirc_options),
        Code.available_compiler_options()
      )

    previous = Code.compiler_options(options)

    try do
      case Kernel.ParallelCompiler.require(files, return_diagnostics: true) do
        {:ok, _modules, _diagnostics} ->
          :ok

        {:error, errors, _diagnostics} ->
          raise "could not load the test files: #{inspect(errors)}"
      end
    after
      Code.compiler_options(previous)
    end
  end
end
