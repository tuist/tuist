defmodule Tuist.Tests.Enumeration do
  @moduledoc """
  The tests a run could have executed (`Tuist.Tests.EnumeratedTest`), as the
  client listed them without running any, and what the run made of them:
  which candidates it ran and which it left out.

  The list is every candidate whatever the run's filters were, so on a
  selective run the difference with `test_case_runs` is the set the selection
  skipped. A generated project that prunes skipped targets from the workspace
  lists only what is left in it.

  Behind the account's coverage flag with the rest of coverage and test
  selection (`Tuist.Tests.Coverage.enabled_for_project?/1`): nothing is stored
  and nothing is reported while it is off.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.EnumeratedTest
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 5_000

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
      display_names = display_names(project_id)

      tests
      |> Stream.map(&row(&1, project_id, test_run_id, inserted_at, display_names))
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(EnumeratedTest, &1))
    end

    :ok
  end

  @doc """
  How many tests the run could have executed, how many of them are enabled,
  and how many enabled ones it did not run. Nil when the client enumerated
  none.
  """
  def summary(%{id: test_run_id, project_id: project_id}) do
    with true <- Coverage.enabled_for_project?(project_id),
         {:ok, test_run_id} <- Ecto.UUID.cast(test_run_id) do
      summary(project_id, test_run_id)
    else
      _ -> nil
    end
  end

  defp summary(project_id, test_run_id) do
    totals =
      ClickHouseRepo.one(
        from(e in subquery(enumerated_query(project_id, test_run_id)),
          select: %{
            enumerated: count(e.test_case_id),
            enabled: fragment("countIf(?)", e.enabled)
          }
        )
      )

    case totals do
      %{enumerated: 0} -> nil
      nil -> nil
      totals -> Map.put(totals, :not_run, ClickHouseRepo.aggregate(not_run_query(project_id, test_run_id), :count))
    end
  end

  @doc """
  The enabled tests the run did not execute, by module, suite and name.
  """
  def list_not_run(%{id: test_run_id, project_id: project_id}, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 50)

    ClickHouseRepo.all(
      from(e in subquery(not_run_query(project_id, test_run_id)),
        order_by: [asc: e.module_name, asc: e.suite_name, asc: e.name],
        limit: ^page_size,
        offset: ^((page - 1) * page_size)
      )
    )
  end

  @doc """
  What the API and the MCP tool return for a run: `summary/1` with a page of
  `list_not_run/2`.
  """
  def payload(summary, tests) do
    %{
      enumerated_test_count: summary.enumerated,
      enabled_test_count: summary.enabled,
      not_run_test_count: summary.not_run,
      tests: Enum.map(tests, &Map.take(&1, [:test_case_id, :module_name, :suite_name, :name]))
    }
  end

  defp not_run_query(project_id, test_run_id) do
    ran =
      from(r in TestCaseRun,
        where: r.project_id == ^project_id and r.test_run_id == ^test_run_id and not is_nil(r.test_case_id),
        select: r.test_case_id
      )

    from(e in subquery(enumerated_query(project_id, test_run_id)),
      where: e.enabled and e.test_case_id not in subquery(ran)
    )
  end

  defp enumerated_query(project_id, test_run_id) do
    from(e in EnumeratedTest,
      where: e.project_id == ^project_id and e.test_run_id == ^test_run_id,
      group_by: e.test_case_id,
      select: %{
        test_case_id: e.test_case_id,
        module_name: fragment("argMax(?, ?)", e.module_name, e.inserted_at),
        suite_name: fragment("argMax(?, ?)", e.suite_name, e.inserted_at),
        name: fragment("argMax(?, ?)", e.name, e.inserted_at),
        enabled: fragment("argMax(?, ?)", e.enabled, e.inserted_at)
      }
    )
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

  # The display name each function was last recorded under. Only tests
  # declared with a display name have a row here, so it stays small however
  # large the suite.
  defp display_names(project_id) do
    from(e in EnumeratedTest,
      where: e.project_id == ^project_id and e.function_name != "",
      group_by: [e.module_name, e.suite_name, e.function_name],
      select: {{e.module_name, e.suite_name, e.function_name}, fragment("argMax(?, ?)", e.name, e.inserted_at)}
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
