defmodule Cache.Finch.PromExPlugin do
  @moduledoc """
  Prometheus metrics for Finch pool utilization.
  """

  use PromEx.Plugin

  alias Cache.Finch.Pools

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :cache_finch_pool_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_pool_metrics, []},
      [
        last_value(
          [:cache, :prom_ex, :finch, :pool, :available_connections],
          event_name: [:cache, :prom_ex, :finch, :pool],
          measurement: :available_connections,
          description: "Total available connections across Finch pools.",
          tags: [:url],
          tag_values: &pool_tag_values/1
        ),
        last_value(
          [:cache, :prom_ex, :finch, :pool, :in_use_connections],
          event_name: [:cache, :prom_ex, :finch, :pool],
          measurement: :in_use_connections,
          description: "Total in-use connections across Finch pools.",
          tags: [:url],
          tag_values: &pool_tag_values/1
        ),
        last_value(
          [:cache, :prom_ex, :finch, :pool, :size],
          event_name: [:cache, :prom_ex, :finch, :pool],
          measurement: :pool_size,
          description: "Total configured size across Finch pools.",
          tags: [:url],
          tag_values: &pool_tag_values/1
        )
      ]
    )
  end

  @doc false
  def execute_pool_metrics do
    Enum.each(Pools.urls(), &emit_pool_metrics/1)
  end

  defp emit_pool_metrics(url) do
    case Finch.get_pool_status(Cache.Finch, url) do
      {:ok, []} ->
        :ok

      {:ok, pools} ->
        totals =
          Enum.reduce(pools, empty_pool_totals(), fn pool, totals ->
            %{
              available_connections: totals.available_connections + pool.available_connections,
              in_use_connections: totals.in_use_connections + pool.in_use_connections,
              pool_size: totals.pool_size + pool.pool_size
            }
          end)

        :telemetry.execute(
          [:cache, :prom_ex, :finch, :pool],
          totals,
          %{url: url}
        )

      {:error, _reason} ->
        :ok
    end
  end

  defp pool_tag_values(metadata) do
    %{url: metadata.url}
  end

  defp empty_pool_totals do
    %{available_connections: 0, in_use_connections: 0, pool_size: 0}
  end
end
