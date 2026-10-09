defmodule Tuist.Tests.Coverage.Xcode do
  @moduledoc """
  What Xcode's coverage depends on that only Xcode builds say: whether a run
  took targets from the binary cache. A cached target is a prebuilt binary
  without coverage counters, so the code its tests executed in it is never
  measured (`Tuist.Tests.Coverage.Instrumentation`).
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
    events =
      run_ids
      |> Coverage.id_chunks()
      |> Enum.flat_map(fn runs ->
        ClickHouseRepo.all(
          from(e in Event, where: e.project_id == ^project_id and e.test_run_id in ^runs, select: {e.id, e.test_run_id})
        )
      end)
      |> Map.new()

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where:
            t.command_event_id in ^ids and fragment("? != 'miss'", t.binary_cache_hit) and t.external_hash == "",
          distinct: true,
          select: t.command_event_id
        )
      )
    end)
    |> Enum.map(&events[&1])
    |> Enum.uniq()
  end
end
