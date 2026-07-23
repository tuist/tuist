defmodule Tuist.Kura.Telemetry do
  @moduledoc """
  Telemetry events for Kura control-plane reconciliation.

  The runner-cache reconciliation status is a level rather than an event
  count: `1` means the feature-flag cohort is unsafe or unavailable and
  reconciliation is preserving the current nodes; `0` means the cohort is
  safe to reconcile. Emitting both states lets the exported last-value metric
  return to healthy immediately after the flag is repaired.
  """

  def event_name_runner_cache_reconciliation, do: [:tuist, :kura, :runner_cache, :reconciliation]

  def runner_cache_reconciliation(paused, metadata \\ %{}) when is_boolean(paused) and is_map(metadata) do
    :telemetry.execute(
      event_name_runner_cache_reconciliation(),
      %{paused: if(paused, do: 1, else: 0)},
      metadata
    )
  end
end
