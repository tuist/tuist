defmodule Tuist.ClickHouse.PromExPlugin do
  @moduledoc """
  Exports the dual-write counter and the recurring parity result for the
  migration off ClickHouse Cloud (spec #73).

  A mirrored write that fails is logged and otherwise ignored, because Cloud is
  the system of record for the whole of that stage and a request must not fail
  or slow down because the in-cluster server is unreachable. That decision only
  holds if the failures are visible somewhere, and a log line is not a signal
  anybody watches: this counter is what says whether the mirror is keeping up,
  between the parity runs that say whether it actually lost anything.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:tuist_clickhouse_shadow_write_event_metrics, [
        counter(
          [:tuist, :clickhouse, :shadow_write, :count],
          event_name: [:tuist, :clickhouse, :shadow_write],
          measurement: :count,
          description: "Writes mirrored onto the in-cluster ClickHouse, by statement kind and outcome.",
          tags: [:kind, :result]
        )
      ]),
      # The number of tables, not a pass/fail, because "how much diverged" is
      # the question during a dual-write soak. Alert on this going above zero:
      # a mirrored write that is lost is lost permanently, so the sooner it is
      # seen the smaller the window a repair has to re-copy.
      Event.build(:tuist_clickhouse_parity_event_metrics, [
        last_value(
          [:tuist, :clickhouse, :parity, :differing],
          event_name: [:tuist, :clickhouse, :parity],
          measurement: :differing,
          description: "Tables whose fingerprints differ between the two ClickHouse servers over the last window."
        ),
        last_value(
          [:tuist, :clickhouse, :parity, :compared],
          event_name: [:tuist, :clickhouse, :parity],
          measurement: :compared,
          description: "Tables compared by the most recent recurring parity check."
        )
      ])
    ]
  end
end
