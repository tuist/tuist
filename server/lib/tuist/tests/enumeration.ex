defmodule Tuist.Tests.Enumeration do
  @moduledoc """
  The tests a run could have executed (`Tuist.Tests.EnumeratedTest`), as the
  client listed them without running any.

  The list is every candidate whatever the run's filters were, so on a
  selective run the difference with `test_case_runs` is the set the selection
  skipped. A generated project that prunes skipped targets from the workspace
  lists only what is left in it.

  Behind the account's coverage flag with the rest of coverage and test
  selection (`Tuist.Tests.Coverage.enabled_for_project?/1`): nothing is stored
  while it is off.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.EnumeratedTest

  @insert_chunk_size 5_000
  @lookup_chunk_size 1_000

  @doc """
  Stores the tests a run's client enumerated. `tests` are maps with
  `module`, `suite`, `name`, `enabled` and, for a test the results report
  under a display name, `function`, atom or string keyed.

  A test must have the identity its runs have, or it reads as enumerated and
  never run. The client names a test after the result it produced
  (`@Test("Maps paths") func map()` is `Maps paths`), but a test the run
  skipped produced none, so it arrives as its function. It takes the display
  name an earlier run of the project recorded for that function.
  """
  def record(_test, nil), do: :ok
  def record(_test, []), do: :ok

  def record(%{id: test_run_id, project_id: project_id}, tests) when is_list(tests) do
    if Coverage.enabled_for_project?(project_id) do
      inserted_at = NaiveDateTime.utc_now()
      display_names = display_names(project_id, tests)

      tests
      |> Stream.map(&row(&1, project_id, test_run_id, inserted_at, display_names))
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(EnumeratedTest, &1))
    end

    :ok
  end

  defp row(test, project_id, test_run_id, inserted_at, display_names) do
    module = value(test, :module)
    suite = value(test, :suite) || ""

    {name, function} = identity(value(test, :name), value(test, :function), {module, suite}, display_names)

    if is_binary(module) and module != "" and is_binary(name) and name != "" do
      %{
        project_id: project_id,
        test_run_id: test_run_id,
        test_case_id: Tests.generate_test_case_id(project_id, name, module, suite),
        module_name: module,
        suite_name: suite,
        name: name,
        function_name: if(function == name, do: "", else: function),
        enabled: value(test, :enabled) != false,
        inserted_at: inserted_at
      }
    end
  end

  defp identity(name, function, _key, _display_names) when is_binary(function) and function != "", do: {name, function}

  defp identity(name, _function, {module, suite}, display_names),
    do: {Map.get(display_names, {module, suite, name}, name), name}

  # The display name each function the run sent without one was last
  # recorded under, looked up by function name only for those tests: the
  # table holds every enumerated test of the project's retained runs.
  defp display_names(project_id, tests) do
    tests
    |> Enum.flat_map(fn test ->
      name = value(test, :name)
      function = value(test, :function)

      if is_binary(name) and name != "" and (not is_binary(function) or function == ""), do: [name], else: []
    end)
    |> Enum.uniq()
    |> Enum.chunk_every(@lookup_chunk_size)
    |> Enum.flat_map(fn functions ->
      ClickHouseRepo.all(
        from(e in EnumeratedTest,
          where: e.project_id == ^project_id and e.function_name in ^functions,
          group_by: [e.module_name, e.suite_name, e.function_name],
          select: {{e.module_name, e.suite_name, e.function_name}, fragment("argMax(?, ?)", e.name, e.inserted_at)}
        )
      )
    end)
    |> Map.new()
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
