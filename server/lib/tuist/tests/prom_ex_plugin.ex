defmodule Tuist.Tests.PromExPlugin do
  @moduledoc """
  Defines metrics for test ingestion correctness.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_test_case_run_correction_metrics,
        [
          distribution(
            [:tuist, :tests, :test_case_run, :physical_tuple_count],
            event_name: Telemetry.event_name_test_case_run_flaky_correction(),
            measurement: :physical_tuple_count,
            description: "Physical tuples observed for a corrected logical test case run.",
            reporter_options: [buckets: [1, 2, 3, 4, 8, 16, 32]]
          ),
          sum(
            [:tuist, :tests, :test_case_run, :physical_tuple_multiplicity_violations],
            event_name: Telemetry.event_name_test_case_run_flaky_correction(),
            measurement: :multiplicity_violation,
            description: "Corrected logical test case runs observed with more than two physical tuples."
          ),
          sum(
            [:tuist, :ingestion, :buffer, :dropped_bytes],
            event_name: Telemetry.event_name_ingestion_buffer_dropped(),
            measurement: :bytes,
            description: "Buffered ClickHouse bytes dropped during process shutdown."
          )
        ]
      )
    ]
  end
end
