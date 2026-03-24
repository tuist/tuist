defmodule TuistCommon.Repo.PromExPlugin do
  @moduledoc false

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    metrics_prefix = Keyword.fetch!(opts, :metrics_prefix)
    pool_metrics_event_name = Keyword.fetch!(opts, :pool_metrics_event_name)
    repos = Keyword.fetch!(opts, :repos)

    quote bind_quoted: [
            name: name,
            metrics_prefix: metrics_prefix,
            pool_metrics_event_name: pool_metrics_event_name,
            repos: repos
          ] do
      use PromEx.Plugin

      alias PromEx.MetricTypes.{Event, Polling}
      alias TuistCommon.Repo.PoolMetrics

      @pool_metrics_event_name pool_metrics_event_name
      @repos repos
      @plugin_name name
      @metrics_prefix metrics_prefix

      @impl true
      def event_metrics(_opts) do
        [
          Event.build(
            :"#{@plugin_name}_repo_pool_event_metrics",
            [
              counter(
                @metrics_prefix ++ [:db_connection, :connected],
                event_name: [:db_connection, :connected],
                tags: [:tag],
                description: "The number of pool connections that have been established.",
                measurement: :count
              ),
              counter(
                @metrics_prefix ++ [:db_connection, :disconnected],
                event_name: [:db_connection, :disconnected],
                tags: [:tag],
                description: "The number of pool connections that have been dropped.",
                measurement: :count
              )
            ]
          ),
          Event.build(
            :"#{@plugin_name}_repo_pool_pressure_metrics",
            [
              sum(
                @metrics_prefix ++ [:checkout_queue, :observed],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description:
                  "The sum of queued DB checkout requests observed across repo pool polls.",
                measurement: :checkout_queue_observed
              ),
              counter(
                @metrics_prefix ++ [:checkout_queue, :busy_samples],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description:
                  "The number of repo pool polls where at least one DB checkout was queued.",
                measurement: :checkout_queue_busy_count
              ),
              counter(
                @metrics_prefix ++ [:checkout_queue, :starved_samples],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description:
                  "The number of repo pool polls where DB checkouts were queued and no ready connections were available.",
                measurement: :checkout_queue_starved_count
              )
            ]
          )
        ]
      end

      @impl true
      def polling_metrics(opts) do
        poll_rate = Keyword.get(opts, :poll_rate, 100)

        [
          Polling.build(
            :"#{@plugin_name}_repo_pool_manual_metrics",
            poll_rate,
            {__MODULE__, :execute_repo_pool_metrics_event, []},
            [
              last_value(
                @metrics_prefix ++ [:checkout_queue, :length],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description:
                  "The total number of operations waiting for a DB connection checkout.",
                measurement: :checkout_queue_length
              ),
              last_value(
                @metrics_prefix ++ [:ready_conn, :count],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description: "The number of connections that are available to run queries.",
                measurement: :ready_conn_count
              ),
              last_value(
                @metrics_prefix ++ [:size],
                event_name: @pool_metrics_event_name,
                tags: [:repo, :database],
                description: "The configured number of connections in the pool.",
                measurement: :pool_size
              )
            ]
          )
        ]
      end

      def execute_repo_pool_metrics_event do
        Enum.each(@repos, fn {repo, metadata} ->
          emit_pool_metrics(repo, metadata)
        end)
      end

      defp emit_pool_metrics(repo, metadata) do
        if PoolMetrics.running?(repo) do
          case PoolMetrics.connection_pool_metrics(repo) do
            nil ->
              :ok

            measurements ->
              :telemetry.execute(
                @pool_metrics_event_name,
                enrich_measurements(measurements),
                metadata
              )
          end
        end
      end

      defp enrich_measurements(measurements) do
        checkout_queue_length = Map.get(measurements, :checkout_queue_length, 0)
        ready_conn_count = Map.get(measurements, :ready_conn_count, 0)

        measurements
        |> Map.put(:checkout_queue_observed, checkout_queue_length)
        |> Map.put(:checkout_queue_busy_count, if(checkout_queue_length > 0, do: 1, else: 0))
        |> Map.put(
          :checkout_queue_starved_count,
          if(checkout_queue_length > 0 and ready_conn_count == 0, do: 1, else: 0)
        )
      end
    end
  end
end
