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
