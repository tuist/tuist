defmodule Tuist.Runners.Telemetry do
  @moduledoc """
  Telemetry event names for the customer-runner dispatch path.

  Events are intentionally narrow — one per state transition plus
  the dispatch endpoint and the two recovery workers. The PromEx
  plugin (`Tuist.Runners.PromExPlugin`) projects them into counters
  for throughput, histograms for queue/run/total durations, and
  bounded-cardinality outcome tags.

  Cardinality discipline: `fleet` is the only high-fan-out tag we
  emit (one bucket per RunnerPool, currently O(1)). Per-account
  fan-out is deliberately *not* tagged on event metrics; account-
  level utilisation is exposed as polled aggregate gauges from
  `Tuist.Runners.PromExPlugin` instead.
  """

  def event_name_job_enqueued, do: [:tuist, :runners, :job, :enqueued]
  def event_name_job_claim, do: [:tuist, :runners, :job, :claim]
  def event_name_job_running, do: [:tuist, :runners, :job, :running]
  def event_name_job_completed, do: [:tuist, :runners, :job, :completed]
  def event_name_job_requeued, do: [:tuist, :runners, :job, :requeued]
  def event_name_dispatch_request, do: [:tuist, :runners, :dispatch, :request]
  def event_name_recovery, do: [:tuist, :runners, :recovery]
  def event_name_webhook, do: [:tuist, :runners, :webhook]

  def event_name_queue_length, do: [:tuist, :runners, :queue, :length]
  def event_name_claims_count, do: [:tuist, :runners, :claims, :count]
  def event_name_pool_replicas, do: [:tuist, :runners, :pool, :replicas]
end
