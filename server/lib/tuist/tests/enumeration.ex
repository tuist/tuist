defmodule Tuist.Tests.Enumeration do
  @moduledoc """
  The tests a run could have executed (`Tuist.Tests.EnumeratedTest`), as the
  client listed them without running any, and what the run made of them:
  which candidates it ran and which it left out.

  The list is every candidate whatever the run's filters were, so on a
  selective run the difference with `test_case_runs` is the set the selection
  skipped. A generated project that prunes skipped targets from the workspace
  lists only what is left in it.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.EnumeratedTest
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 5_000

  @doc """
  Stores the tests a run's client enumerated. `tests` are maps with
  `module`, `suite`, `name` and `enabled`, atom or string keyed.
  """
  def record(_test, nil), do: :ok
  def record(_test, []), do: :ok

  def record(%{id: test_run_id, project_id: project_id}, tests) when is_list(tests) do
    inserted_at = NaiveDateTime.utc_now()

    tests
    |> Stream.map(&row(&1, project_id, test_run_id, inserted_at))
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_every(@insert_chunk_size)
    |> Enum.each(&IngestRepo.insert_all(EnumeratedTest, &1))
  end

  @doc """
  How many tests the run could have executed, how many of them are enabled,
  and how many enabled ones it did not run. Nil when the client enumerated
  none.
  """
  def summary(%{id: test_run_id, project_id: project_id}) do
    case Ecto.UUID.cast(test_run_id) do
      {:ok, test_run_id} -> summary(project_id, test_run_id)
      :error -> nil
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

  defp row(test, project_id, test_run_id, inserted_at) do
    module = value(test, :module)
    name = value(test, :name)
    suite = value(test, :suite) || ""

    if is_binary(module) and module != "" and is_binary(name) and name != "" do
      %{
        project_id: project_id,
        test_run_id: test_run_id,
        test_case_id: Tests.generate_test_case_id(project_id, name, module, suite),
        module_name: module,
        suite_name: suite,
        name: name,
        enabled: value(test, :enabled) != false,
        inserted_at: inserted_at
      }
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
