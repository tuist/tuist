defmodule Tuist.ClickHouseRepo.PromExPlugin do
  @moduledoc """
  Prometheus metrics for every query `Tuist.ClickHouseRepo` runs: a count and a
  duration histogram, both split by outcome.

  The `result` tag is `ok`, `clickhouse_<code>` for an error ClickHouse returned
  (159 is `TIMEOUT_EXCEEDED`, 241 the memory limit), `transport_<reason>` for a
  connection the client dropped (`transport_closed` is what a client-side
  timeout looks like), `queue_timeout` for a pool checkout that never got a
  connection, and `connection_error` or `error` for anything else.
  """
  use PromEx.Plugin

  @query_event [:tuist, :click_house_repo, :query]
  @metric_prefix [:tuist, :clickhouse, :query]

  # Spans the interactive range up to and past the server- and client-side
  # timeouts configured on the repo.
  @duration_buckets [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 15_000, 20_000, 30_000]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_clickhouse_query_event_metrics,
        [
          counter(
            @metric_prefix ++ [:count],
            event_name: @query_event,
            description: "Queries run against the read-only ClickHouse repo, by outcome.",
            tag_values: &tag_values/1,
            tags: [:repo, :result]
          ),
          distribution(
            @metric_prefix ++ [:duration, :milliseconds],
            event_name: @query_event,
            measurement: :total_time,
            description: "Wall-clock of a read-only ClickHouse query, pool wait included, by outcome.",
            reporter_options: [buckets: @duration_buckets],
            tag_values: &tag_values/1,
            tags: [:repo, :result],
            unit: {:native, :millisecond}
          )
        ]
      )
    ]
  end

  def tag_values(%{result: result}) do
    %{repo: "clickhouse_read", result: result_tag(result)}
  end

  defp result_tag({:ok, _result}), do: "ok"
  defp result_tag({:error, %Ch.Error{code: code}}) when is_integer(code), do: "clickhouse_#{code}"
  defp result_tag({:error, %Ch.Error{}}), do: "clickhouse"
  defp result_tag({:error, %DBConnection.ConnectionError{reason: :queue_timeout}}), do: "queue_timeout"
  defp result_tag({:error, %DBConnection.ConnectionError{}}), do: "connection_error"
  defp result_tag({:error, %Mint.TransportError{reason: reason}}) when is_atom(reason), do: "transport_#{reason}"
  defp result_tag({:error, %Mint.TransportError{}}), do: "transport_error"
  defp result_tag({:error, _error}), do: "error"
end
