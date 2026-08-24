defmodule Tuist.Kura.Telemetry do
  @moduledoc """
  Telemetry contract for the demand-driven Kura lifecycle.

  These are the inputs for deciding whether the 60-day Air pressure policy is
  acceptable and whether another machine is needed, so they are emitted from
  the transitions themselves rather than reconstructed later:

    * `provisioned` separates cold returns from first provisions, which is the
      cold-return rate.
    * `ready` carries the wall-clock from provisioning to serving, which on a
      cold return is the latency an archived account pays to come back.
    * `drain_pending`, `archive_cancelled`, and `archived` bracket the
      reclamation, with reclaimed bytes and drain duration on the last.
    * `resolution_refused` counts the accounts that never reach any of the
      above, because their plan or storage region resolved to no pool.

  That last one is the only signal a refusal produces. A refused account keeps
  being served by whatever lane it is already on, raises nothing, and appears
  in none of the transition counters precisely because it has no instance to
  transition, so an entire class of accounts can sit unprovisioned for months
  without it.

  `plan` and `region` are both bounded (four plans, a handful of regions), so
  tagging by them is safe, as is `reason`. Account is never a tag.
  """

  @prefix [:tuist, :kura, :lifecycle]

  def event_name_provisioned, do: @prefix ++ [:provisioned]
  def event_name_ready, do: @prefix ++ [:ready]
  def event_name_drain_pending, do: @prefix ++ [:drain_pending]
  def event_name_archive_cancelled, do: @prefix ++ [:archive_cancelled]
  def event_name_archived, do: @prefix ++ [:archived]
  def event_name_resolution_refused, do: @prefix ++ [:resolution_refused]

  def provisioned(plan, region, cold_return?) do
    :telemetry.execute(event_name_provisioned(), %{count: 1}, %{
      plan: to_string(plan),
      region: region,
      cold_return: to_string(cold_return?)
    })
  end

  def ready(plan, region, cold_return?, time_to_ready_ms) do
    :telemetry.execute(
      event_name_ready(),
      %{count: 1, time_to_ready_ms: time_to_ready_ms},
      %{plan: to_string(plan), region: region, cold_return: to_string(cold_return?)}
    )
  end

  def drain_pending(plan, region, reason) do
    :telemetry.execute(event_name_drain_pending(), %{count: 1}, %{
      plan: to_string(plan),
      region: region,
      reason: to_string(reason)
    })
  end

  def archive_cancelled(plan, region) do
    :telemetry.execute(event_name_archive_cancelled(), %{count: 1}, %{
      plan: to_string(plan),
      region: region
    })
  end

  def archived(plan, region, reclaimed_bytes, drain_duration_ms) do
    :telemetry.execute(
      event_name_archived(),
      %{count: 1, reclaimed_bytes: reclaimed_bytes, drain_duration_ms: drain_duration_ms},
      %{plan: to_string(plan), region: region}
    )
  end

  # No region tag: a refusal is the absence of one.
  def resolution_refused(plan, reason) do
    :telemetry.execute(event_name_resolution_refused(), %{count: 1}, %{
      plan: to_string(plan),
      reason: to_string(reason)
    })
  end
end
