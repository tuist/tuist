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

  A hit counts only when its binary replaced the target. The client fetches a
  binary for every hit but replaces a target only when its direct dependencies
  were all replaced, so a hit above a miss is built from source (or not built
  at all) and its fetched binary goes unused. The run's own targets say which:
  a hit is replaced when every target its `dependencies` name is a replaced
  hit too. A client that reports no dependencies leaves every hit replaced.
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
          where: t.command_event_id in ^ids and fragment("? != 'miss'", t.binary_cache_hit),
          select: %{
            command_event_id: t.command_event_id,
            name: t.name,
            product: t.product,
            external_hash: t.external_hash,
            instrumented: t.binary_cache_instrumented,
            dependencies: t.dependencies
          }
        )
      )
    end)
    |> Enum.group_by(& &1.command_event_id)
    |> Enum.flat_map(fn {event, hits} ->
      replaced = replaced_targets(hits)

      for hit <- hits,
          MapSet.member?(replaced, hit.name),
          hit.external_hash == "" and hit.instrumented != true and hit.product not in @uncounted_products,
          do: {events[event], hit.name}
    end)
    |> Enum.group_by(fn {run_id, _name} -> run_id end, fn {_run_id, name} -> name end)
    |> Map.new(fn {run_id, names} -> {run_id, names |> Enum.uniq() |> Enum.sort()} end)
  end

  # The client's `CacheGraphMutator` rule, over one run's hits: a target is
  # replaced when it is a hit and every direct dependency is replaced, so a
  # miss keeps every target above it as source.
  defp replaced_targets(hits) do
    dependencies =
      Enum.reduce(hits, %{}, &Map.update(&2, &1.name, &1.dependencies, fn deps -> deps ++ &1.dependencies end))

    dependencies
    |> Map.keys()
    |> Enum.reduce(%{}, fn name, memo -> name |> replaced?(dependencies, memo) |> elem(1) end)
    |> Enum.filter(fn {_name, replaced} -> replaced end)
    |> MapSet.new(fn {name, _replaced} -> name end)
  end

  defp replaced?(name, dependencies, memo) do
    cond do
      Map.has_key?(memo, name) ->
        {memo[name], memo}

      not Map.has_key?(dependencies, name) ->
        {false, Map.put(memo, name, false)}

      true ->
        {replaced, memo} =
          Enum.reduce_while(dependencies[name], {true, Map.put(memo, name, false)}, fn dependency, {true, memo} ->
            case replaced?(dependency, dependencies, memo) do
              {true, memo} -> {:cont, {true, memo}}
              {false, memo} -> {:halt, {false, memo}}
            end
          end)

        {replaced, Map.put(memo, name, replaced)}
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
