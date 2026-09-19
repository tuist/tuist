defmodule Tuist.Registry.Swift.PromExPlugin do
  @moduledoc """
  Prometheus metrics for the Swift package registry writer.

  These are coverage signals, not availability signals. The July 2026 incident
  ran for days on a pod that was Ready with zero restarts while thousands of
  rate-limit failures silently dropped scheduled catalog work, so "the writer is
  up" and "the writer is keeping the catalog current" have to be separately
  observable.

  Counters only, with a small fixed set of reasons as labels. Package identity
  deliberately stays out: a catalog rotation touches tens of thousands of
  packages, and the question these answer is how much scheduled coverage was
  lost, not which package lost it. That belongs in the logs, which name the
  package the pass stopped at.
  """
  use PromEx.Plugin

  alias Tuist.Registry.Swift.ReleaseWorker
  alias Tuist.Registry.Swift.SyncWorker

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:tuist_registry_swift_sync_event_metrics, [
        # `sum`, not `counter`: a counter increments by one per event regardless
        # of the measurement, so counting a "packages deferred" event would
        # report the number of throttled passes under a name that reads as a
        # number of packages.
        sum(
          [:tuist, :registry, :swift, :sync, :coverage_deferred, :packages, :total],
          event_name: SyncWorker.coverage_deferred_event_name(),
          measurement: :packages,
          description: "Catalog packages a sync pass was scheduled to visit and deferred instead.",
          tags: [:reason],
          tag_values: &tag_values/1
        ),
        # The pass count, which is what the alert threshold is keyed on: a pass
        # that never got as far as listing the catalog defers zero packages but
        # is still a pass that mirrored nothing.
        counter(
          [:tuist, :registry, :swift, :sync, :coverage_deferred, :total],
          event_name: SyncWorker.coverage_deferred_event_name(),
          description: "Sync passes that stopped short of the coverage they were scheduled for.",
          tags: [:reason],
          tag_values: &tag_values/1
        ),
        sum(
          [:tuist, :registry, :swift, :sync, :package_skipped, :total],
          event_name: SyncWorker.package_skipped_event_name(),
          measurement: :packages,
          description: "Catalog packages a sync pass passed over without reading their tags.",
          tags: [:reason],
          tag_values: &tag_values/1
        ),
        sum(
          [:tuist, :registry, :swift, :release, :deferred, :total],
          event_name: ReleaseWorker.release_deferred_event_name(),
          measurement: :releases,
          description: "Release jobs deferred rather than run, keeping their arguments queued.",
          tags: [:reason],
          tag_values: &tag_values/1
        )
      ])
    ]
  end

  defp tag_values(metadata) do
    %{reason: to_string(Map.get(metadata, :reason, "unknown"))}
  end
end
