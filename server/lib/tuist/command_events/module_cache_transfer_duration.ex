defmodule Tuist.CommandEvents.ModuleCacheTransferDuration do
  @moduledoc """
  The per-command wall-clock time spent transferring module (binary) cache
  artifacts, surfaced as the run's overall module cache fetch time.

  Kept in its own table (rather than a `command_events` column) so it stays
  symmetric with `Tuist.CommandEvents.ModuleCacheOutput` and does not require
  re-populating the `command_events` materialized views. The per-operation
  durations in `module_cache_outputs` cannot be summed into this because
  transfers run concurrently.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "module_cache_transfer_durations" do
    field :command_event_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :duration_ms, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(command_event_id, project_id, duration_ms) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{
        command_event_id: command_event_id,
        project_id: project_id,
        duration_ms: duration_ms && trunc(duration_ms),
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [:command_event_id, :project_id, :duration_ms, :inserted_at]
    )
    |> Ecto.Changeset.validate_required([:command_event_id, :project_id, :duration_ms, :inserted_at])
  end
end
