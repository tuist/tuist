defmodule Tuist.Tests.Coverage.Xcode do
  @moduledoc """
  What Xcode's coverage depends on that only Xcode builds say, from the
  targets each run's command event reported: which targets a run took from
  the binary cache without coverage counters (the code its tests executed in
  them is never measured: `Tuist.Tests.Coverage.Instrumentation`), and the
  hash and hit selective testing gave each test target.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.Tests.Coverage
  alias Tuist.Xcode.XcodeTarget

  @test_products ["unit_tests", "ui_tests"]
  # Products with no code a test could execute: a resource bundle holds none, and
  # a macro's runs at compile time. Taken from the cache, they hide nothing.
  @uncounted_products ["bundle", "macro"]

  @doc """
  The repository targets each run took from the binary cache without coverage
  counters, as `%{test_run_id => [target name]}`; a run that took none has no
  entry. A remote package's targets carry its revision as their
  `external_hash`, and no coverage is kept outside the repository anyway; a
  local package has none, so it counts. Resource bundles and macros hold no
  code a test executes and never count. A hit the client reported as
  instrumented (`binary_cache_instrumented`) carries counters and is left out;
  a client that reports nothing leaves its hits counting as plain.
  """
  def uninstrumented_targets(_project_id, []), do: %{}

  def uninstrumented_targets(project_id, run_ids) do
    events = command_events(project_id, run_ids)

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where:
            t.command_event_id in ^ids and fragment("? != 'miss'", t.binary_cache_hit) and t.external_hash == "" and
              fragment("ifNull(?, false) = false", t.binary_cache_instrumented) and
              t.product not in ^@uncounted_products,
          distinct: true,
          select: {t.command_event_id, t.name}
        )
      )
    end)
    |> Enum.group_by(fn {event, _name} -> events[event] end, fn {_event, name} -> name end)
    |> Map.new(fn {run_id, names} -> {run_id, names |> Enum.uniq() |> Enum.sort()} end)
  end

  @doc """
  The test targets of each run that link, directly or through other targets,
  a repository target the run took from the binary cache without coverage
  counters, as `{test_run_id, test target name}` pairs. What their tests
  executed in that code went unmeasured, so the run is no source for them.
  Targets are linked by the direct dependency names each run reported; a
  client that reported none links nothing.
  """
  def uninstrumented_test_targets(_project_id, []), do: MapSet.new()

  def uninstrumented_test_targets(project_id, run_ids) do
    events = command_events(project_id, run_ids)

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids,
          distinct: true,
          select: %{
            command_event_id: t.command_event_id,
            name: t.name,
            product: t.product,
            dependencies: t.dependencies,
            plain:
              fragment(
                "? != 'miss' AND ? = '' AND ifNull(?, false) = false",
                t.binary_cache_hit,
                t.external_hash,
                t.binary_cache_instrumented
              )
          }
        )
      )
    end)
    |> Enum.group_by(& &1.command_event_id)
    |> Enum.flat_map(fn {event, targets} ->
      plain =
        targets
        |> Enum.filter(&(&1.plain in [true, 1] and &1.product not in @uncounted_products))
        |> MapSet.new(& &1.name)

      dependencies = Map.new(targets, &{&1.name, &1.dependencies})

      targets
      |> Enum.filter(&(&1.product in @test_products and links_plain?(&1.name, dependencies, plain)))
      |> Enum.map(&{events[event], &1.name})
    end)
    |> MapSet.new()
  end

  defp links_plain?(name, dependencies, plain) do
    links_plain?([name], dependencies, plain, MapSet.new())
  end

  defp links_plain?([], _dependencies, _plain, _seen), do: false

  defp links_plain?([name | rest], dependencies, plain, seen) do
    cond do
      MapSet.member?(seen, name) -> links_plain?(rest, dependencies, plain, seen)
      MapSet.member?(plain, name) -> true
      true -> links_plain?(Map.get(dependencies, name, []) ++ rest, dependencies, plain, MapSet.put(seen, name))
    end
  end

  @doc """
  The selective-testing hash and hit each run's command event reported per
  target. A run that ignored selective testing still hashes its targets,
  and reports them as misses. The targets are read by command event, which
  their table's `proj_by_command_event` projection is ordered by: joined
  to the events, nothing bounded the read of a table ordered by time.
  """
  def selective_testing_hashes(_project_id, []), do: []

  def selective_testing_hashes(project_id, run_ids) do
    events = command_events(project_id, run_ids)

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids and not is_nil(t.selective_testing_hash),
          distinct: true,
          select: %{
            command_event_id: t.command_event_id,
            name: t.name,
            hash: t.selective_testing_hash,
            hit: t.selective_testing_hit
          }
        )
      )
    end)
    |> Enum.map(fn target ->
      target |> Map.delete(:command_event_id) |> Map.put(:test_run_id, events[target.command_event_id])
    end)
    |> Enum.uniq()
  end

  defp command_events(project_id, run_ids) do
    run_ids
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn runs ->
      ClickHouseRepo.all(
        from(e in Event, where: e.project_id == ^project_id and e.test_run_id in ^runs, select: {e.id, e.test_run_id})
      )
    end)
    |> Map.new()
  end
end
