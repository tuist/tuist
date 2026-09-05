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

  # Which cache-volume residency outcome decided the candidate handed to a
  # polling node. The host's warm/cold materialize counter is the ground truth
  # for cache warmth, but it cannot say why a job landed cold; this can, and
  # the two answers call for opposite fixes. Emitted on the macOS fleet only,
  # where cache volumes exist.
  def event_name_dispatch_affinity, do: [:tuist, :runners, :dispatch, :affinity]
  def event_name_recovery, do: [:tuist, :runners, :recovery]
  def event_name_webhook, do: [:tuist, :runners, :webhook]

  # The Buildkite lane's counterpart to `event_name_webhook`. Carries both
  # what the queue held and what we reserved: the gap between them is a
  # sibling stack taking our jobs, which no other signal would show.
  def event_name_buildkite_poll, do: [:tuist, :runners, :buildkite, :poll]

  def event_name_queue_length, do: [:tuist, :runners, :queue, :length]

  # Queued jobs excluded from the autoscaler's demand signal because
  # their account is at its concurrency limit. Sustained non-zero means
  # a customer is queueing past their cap: the queue is deep but the
  # fleet must not grow for it. Without this the withholding is
  # invisible, since dispatch declines those jobs at `Logger.debug`.
  def event_name_queue_withheld, do: [:tuist, :runners, :queue, :withheld]
  def event_name_claims_count, do: [:tuist, :runners, :claims, :count]
  def event_name_pool_replicas, do: [:tuist, :runners, :pool, :replicas]
  def event_name_session_clamp, do: [:tuist, :runners, :session, :clamped]

  # Jobs whose ClickHouse row is still non-terminal after the outbox
  # flush has had time to settle, while Postgres holds a terminal state.
  def event_name_replica_divergence, do: [:tuist, :runners, :replica, :divergence]
end
