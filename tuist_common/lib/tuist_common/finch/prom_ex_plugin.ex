defmodule TuistCommon.Finch.PromExPlugin do
  @moduledoc """
  Parameterised PromEx plugin for Finch pool utilisation. Used by every
  service that runs its own Finch pools (cache, standalone registry).

  ## Opts

    * `:prefix` — atom prefixed to every metric path / event name
      (e.g. `:cache`, `:tuist_registry`)
    * `:finch_name` — the Finch process name to query
      (e.g. `Cache.Finch`, `TuistRegistry.Finch`)
    * `:pools_module` — module exposing `urls/0` listing pool URLs
    * `:poll_rate` — polling interval in ms (default 15_000)
  """

  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    prefix = Keyword.fetch!(opts, :prefix)
    finch_name = Keyword.fetch!(opts, :finch_name)
    pools_module = Keyword.fetch!(opts, :pools_module)
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      polling_id(prefix),
      poll_rate,
      {__MODULE__, :execute_pool_metrics, [finch_name, pools_module, prefix]},
      pool_metrics(prefix)
    )
  end

  @doc false
  def execute_pool_metrics(finch_name, pools_module, prefix) do
    Enum.each(pools_module.urls(), &emit_pool_metrics(finch_name, prefix, &1))
  end

  defp emit_pool_metrics(finch_name, prefix, url) do
    case Finch.get_pool_status(finch_name, url) do
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

        :telemetry.execute([prefix, :prom_ex, :finch, :pool], totals, %{url: url})

      {:error, _reason} ->
        :ok
    end
  end

  defp pool_metrics(prefix) do
    event = [prefix, :prom_ex, :finch, :pool]
    tag_values = fn metadata -> %{url: metadata.url} end

    [
      last_value(
        event ++ [:available_connections],
        event_name: event,
        measurement: :available_connections,
        description: "Total available connections across Finch pools.",
        tags: [:url],
        tag_values: tag_values
      ),
      last_value(
        event ++ [:in_use_connections],
        event_name: event,
        measurement: :in_use_connections,
        description: "Total in-use connections across Finch pools.",
        tags: [:url],
        tag_values: tag_values
      ),
      last_value(
        event ++ [:size],
        event_name: event,
        measurement: :pool_size,
        description: "Total configured size across Finch pools.",
        tags: [:url],
        tag_values: tag_values
      )
    ]
  end

  defp empty_pool_totals do
    %{available_connections: 0, in_use_connections: 0, pool_size: 0}
  end

  defp polling_id(prefix), do: :"#{prefix}_finch_pool_polling_metrics"
end
