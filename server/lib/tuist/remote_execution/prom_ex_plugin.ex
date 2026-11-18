defmodule Tuist.RemoteExecution.PromExPlugin do
  @moduledoc "Remote execution scheduling outcomes, bounded by fixed outcome sets; no account or project labels."
  use PromEx.Plugin

  @duration_buckets [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 10_000, 60_000, 600_000]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:remote_execution, [
        counter([:tuist, :remote_execution, :submissions, :total],
          event_name: [:tuist, :remote_execution, :submission],
          tags: [:outcome],
          description: "Actions submitted to schedulers: accepted, joined to an identical in-flight action, or refused."
        ),
        counter([:tuist, :remote_execution, :operations, :total],
          event_name: [:tuist, :remote_execution, :operation],
          tags: [:outcome],
          description: "Scheduler operations completed, by status."
        ),
        distribution([:tuist, :remote_execution, :operation, :duration, :milliseconds],
          event_name: [:tuist, :remote_execution, :operation],
          measurement: :duration,
          unit: :millisecond,
          tags: [:outcome],
          reporter_options: [buckets: @duration_buckets],
          description: "Time from submission to completion of a scheduler operation."
        ),
        distribution([:tuist, :remote_execution, :operation, :queue_time, :milliseconds],
          event_name: [:tuist, :remote_execution, :operation],
          measurement: :queue_time,
          unit: :millisecond,
          tags: [:outcome],
          reporter_options: [buckets: @duration_buckets],
          description: "Time an operation waited for a VM before running."
        ),
        distribution([:tuist, :remote_execution, :prepare, :duration, :milliseconds],
          event_name: [:tuist, :remote_execution, :prepare],
          measurement: :duration,
          unit: :millisecond,
          tags: [:outcome],
          reporter_options: [buckets: @duration_buckets],
          description: "VM reservation, creation and preparation, by outcome."
        ),
        counter([:tuist, :remote_execution, :leases, :total],
          event_name: [:tuist, :remote_execution, :lease],
          tags: [:outcome],
          description: "Gateway leases: claimed, returned unclaimed, failed, timed out without a VM, or unsupported."
        )
      ])
    ]
  end
end
