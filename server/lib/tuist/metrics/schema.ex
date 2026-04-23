defmodule Tuist.Metrics.Schema do
  @moduledoc """
  Declarative definitions of the per-account metrics exposed through the
  Prometheus-compatible scrape endpoint.

  Each metric lists its name, type, help text, labels, and (for histograms) the
  bucket schedule. Labels come from system-specific vocabularies: Xcode metrics
  use `scheme`, Gradle uses `module`, CLI uses `command`. We deliberately do
  not mix them into a generic cross-system abstraction — misleading
  aggregations are worse than asking customers with mixed stacks to use PromQL
  unions.

  Cardinality is bounded by:

    * omitting high-cardinality dimensions (commit SHA, branch, user),
    * including version labels only where they drift slowly,
    * sharing one histogram bucket schedule across metrics.
  """

  @default_buckets [0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600, 1200]
  @sub_second_buckets [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30]

  def default_buckets, do: @default_buckets
  def sub_second_buckets, do: @sub_second_buckets

  @definitions [
    # ---- Xcode -----------------------------------------------------------
    %{
      name: "tuist_xcode_build_runs_total",
      type: :counter,
      namespace: :xcode,
      help: "Total number of Xcode build runs recorded for the account.",
      labels: [:project, :scheme, :is_ci, :status, :xcode_version, :macos_version]
    },
    %{
      name: "tuist_xcode_build_run_duration_seconds",
      type: :histogram,
      namespace: :xcode,
      help: "Observed duration of Xcode build runs in seconds.",
      # Histogram labels are deliberately narrower than the counter's. Every
      # extra label multiplies by ~13 ETS rows (count + sum + 11 buckets), so
      # version dimensions live only on the counter where drill-down queries
      # happen. Percentile dashboards aggregate across versions anyway.
      labels: [:project, :scheme, :is_ci, :status],
      buckets: @default_buckets
    },
    %{
      name: "tuist_xcode_test_runs_total",
      type: :counter,
      namespace: :xcode,
      help: "Total number of Xcode test runs recorded for the account.",
      labels: [:project, :scheme, :is_ci, :status, :xcode_version, :macos_version]
    },
    %{
      name: "tuist_xcode_test_run_duration_seconds",
      type: :histogram,
      namespace: :xcode,
      help: "Observed duration of Xcode test runs in seconds.",
      labels: [:project, :scheme, :is_ci, :status],
      buckets: @default_buckets
    },
    %{
      name: "tuist_xcode_test_cases_total",
      type: :counter,
      namespace: :xcode,
      help: "Total number of Xcode test case results recorded.",
      labels: [:project, :scheme, :is_ci, :status]
    },
    %{
      name: "tuist_xcode_cache_events_total",
      type: :counter,
      namespace: :xcode,
      help: "Total number of Xcode binary cache events (hit/miss).",
      labels: [:project, :event_type]
    },
    # ---- Gradle ----------------------------------------------------------
    %{
      name: "tuist_gradle_build_runs_total",
      type: :counter,
      namespace: :gradle,
      help: "Total number of Gradle build runs recorded for the account.",
      labels: [:project, :module, :is_ci, :status, :gradle_version, :jvm_version]
    },
    %{
      name: "tuist_gradle_build_run_duration_seconds",
      type: :histogram,
      namespace: :gradle,
      help: "Observed duration of Gradle build runs in seconds.",
      labels: [:project, :module, :is_ci, :status],
      buckets: @default_buckets
    },
    %{
      name: "tuist_gradle_test_runs_total",
      type: :counter,
      namespace: :gradle,
      help: "Total number of Gradle test runs recorded for the account.",
      labels: [:project, :module, :is_ci, :status, :gradle_version, :jvm_version]
    },
    %{
      name: "tuist_gradle_test_run_duration_seconds",
      type: :histogram,
      namespace: :gradle,
      help: "Observed duration of Gradle test runs in seconds.",
      labels: [:project, :module, :is_ci, :status],
      buckets: @default_buckets
    },
    # ---- CLI -------------------------------------------------------------
    %{
      name: "tuist_cli_invocations_total",
      type: :counter,
      namespace: :cli,
      help: "Total number of CLI command invocations recorded for the account.",
      labels: [:project, :command, :is_ci, :status]
    },
    %{
      name: "tuist_cli_invocation_duration_seconds",
      type: :histogram,
      namespace: :cli,
      help: "Observed duration of CLI command invocations in seconds.",
      labels: [:project, :command, :is_ci, :status],
      buckets: @sub_second_buckets
    }
  ]

  @by_name Map.new(@definitions, &{&1.name, &1})

  @doc """
  Returns the ordered list of metric definitions to expose.
  """
  def definitions, do: @definitions

  @doc """
  Returns the definition for a metric name, or `nil` if the name is unknown.
  """
  def fetch(name), do: Map.get(@by_name, name)

  @doc """
  Returns the ordered label tuple for a metric, raising if the metric doesn't
  exist or the provided label map is missing keys.

  Normalising label tuples at ingestion time keeps ETS key layout identical
  across observations regardless of map ordering.
  """
  def label_tuple!(name, labels) do
    %{labels: label_keys} = Map.fetch!(@by_name, name)
    List.to_tuple(Enum.map(label_keys, &Map.fetch!(labels, &1)))
  end
end
