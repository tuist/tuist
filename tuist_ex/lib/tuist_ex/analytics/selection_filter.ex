defmodule TuistEx.Analytics.SelectionFilter do
  @moduledoc false

  # Leaves a coverage-based selection's skip list out of the run, each test
  # by the identity the formatter reports it with: `{module, describe or "",
  # name}`, or a whole module. The server lists what to skip rather than
  # what to run, because a test it hasn't seen, such as one the change adds,
  # must run; so the filter has to name tests exactly and let everything
  # else through.
  #
  # ExUnit's filters can't: each matches one tag, so a name also matches
  # same-named tests in other modules, and a line matches the closest test
  # in every module of a file. `ExUnit.Filters.eval/4`, which the runner
  # calls for every test with its module and name among the tags, is
  # replaced (`ExUnitPatch`) by one that calls ExUnit's and then excludes a
  # listed test ExUnit would have run. Tests ExUnit excludes or skips keep
  # its answer, as `@tag :skip` and quarantine are not selection, and one an
  # include filter picks (`--only`, `file:line`, `--include`) runs, as with
  # any exclusion.

  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.ExUnitPatch
  alias TuistEx.Analytics.Quarantine

  @filters ExUnit.Filters
  @original Module.concat(__MODULE__, OriginalFilters)
  @key {__MODULE__, :skipped}
  @reason "due to tuist_unselected filter"

  @doc "The reason a test the selection left out is excluded with."
  def reason, do: @reason

  @doc """
  Replaces ExUnit's filter evaluation in this VM, which leaves out nothing
  until `skip/1` names what to. `:error` when it can't.
  """
  def install do
    :persistent_term.erase(@key)

    ExUnitPatch.wrap(
      @filters,
      @original,
      :__tuist_ex_selection__,
      [eval: 4],
      quote do
        def eval(include, exclude, tags, collection),
          do: unquote(__MODULE__).eval(unquote(@original), include, exclude, tags, collection)
      end
    )
  end

  @doc "Installs the filter and has it leave `skipped_tests` out of the run."
  def apply(skipped_tests) do
    with :ok <- install() do
      skip(skipped_tests)
    end
  end

  defp skip(skipped_tests) do
    {modules, tests} =
      Enum.reduce(skipped_tests, {MapSet.new(), %{}}, fn
        %{module: module, name: nil}, {modules, tests} ->
          {MapSet.put(modules, module), tests}

        %{module: module, suite: suite, name: name}, {modules, tests} ->
          {modules,
           Map.update(tests, module, MapSet.new([{suite, name}]), &MapSet.put(&1, {suite, name}))}
      end)

    :persistent_term.put(@key, %{modules: modules, tests: tests})
    :ok
  end

  @doc false
  def eval(original, include, exclude, tags, collection) do
    result = original.eval(include, exclude, tags, collection)

    if result == :ok and unselected?(tags) and not included?(original, include, tags, collection),
      do: {:excluded, @reason},
      else: result
  end

  defp unselected?(%{module: module, test: name} = tags) do
    case :persistent_term.get(@key, nil) do
      %{modules: modules, tests: tests} ->
        module_name = inspect(module)

        MapSet.member?(modules, module_name) or
          (Map.has_key?(tests, module_name) and
             MapSet.member?(tests[module_name], suite_and_name(module, name, tags)))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp unselected?(_tags), do: false

  defp suite_and_name(module, name, tags) do
    test = %ExUnit.Test{module: module, name: name, tags: tags}
    {_module, suite, name} = Quarantine.identity(ExUnitFormatter.record(test))
    {suite, name}
  end

  # Whether an include filter picks the test: evaluated as exclusions, the
  # include filters exclude exactly the tests they match.
  defp included?(_original, [], _tags, _collection), do: false

  defp included?(original, include, tags, collection),
    do: match?({:excluded, _}, original.eval([], include, tags, collection))
end
