defmodule Tuist.Tests.Coverage.Xcode do
  @moduledoc """
  What Xcode's coverage depends on that only Xcode builds say, from the
  targets each run's command event reported: whether a run took targets from
  the binary cache (a cached target is a prebuilt binary without coverage
  counters, so the code its tests executed in it is never measured:
  `Tuist.Tests.Coverage.Instrumentation`), and the hash and hit selective
  testing gave each test target.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.Tests.Coverage
  alias Tuist.Xcode.XcodeTarget

  @doc """
  The runs, of the given ones, that took at least one of the repository's
  targets from the binary cache. A remote package's targets carry its
  revision as their `external_hash`, and no coverage is kept outside the
  repository anyway; a local package has none, so it counts.
  """
  def uninstrumented_runs(_project_id, []), do: []

  def uninstrumented_runs(project_id, run_ids) do
    events = command_events(project_id, run_ids)

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids and fragment("? != 'miss'", t.binary_cache_hit) and t.external_hash == "",
          distinct: true,
          select: t.command_event_id
        )
      )
    end)
    |> Enum.map(&events[&1])
    |> Enum.uniq()
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
