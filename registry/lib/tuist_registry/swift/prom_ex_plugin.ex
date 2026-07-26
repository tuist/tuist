defmodule TuistRegistry.Swift.PromExPlugin do
  @moduledoc """
  Prometheus metrics for Swift package registry downloads.

  Replaces the prior `EventsPipeline → /webhooks/registry → ClickHouse`
  path. Per-download events are emitted as PromEx counters scraped by the
  in-cluster Alloy receiver and rolled up in Grafana.

  Cardinality: labels are intentionally limited to `scope` and `name`.
  Adding `version` would multiply the series space by the number of
  versions per package (typically dozens, sometimes hundreds), which is
  not justified by any aggregation we need today. Version-level
  popularity belongs in structured logs or a dedicated ClickHouse path
  if we ever need it.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:tuist_registry_swift_download_event_metrics, [
        counter(
          [:tuist_registry, :swift, :download, :total],
          event_name: [:tuist_registry, :swift, :download],
          description: "Swift package source-archive downloads per scope and name.",
          tags: [:scope, :name],
          tag_values: &tag_values/1
        )
      ]),
      Event.build(:tuist_registry_swift_manifest_event_metrics, [
        counter(
          [:tuist_registry, :swift, :manifest, :total],
          event_name: [:tuist_registry, :swift, :manifest],
          description: "Swift package manifest reads per scope and name.",
          tags: [:scope, :name],
          tag_values: &tag_values/1
        )
      ])
    ]
  end

  defp tag_values(metadata) do
    %{
      scope: to_string(Map.get(metadata, :scope, "unknown")),
      name: to_string(Map.get(metadata, :name, "unknown"))
    }
  end
end
