defmodule Atlas.HTTP do
  @moduledoc false

  @default_finch_name Atlas.Finch
  @default_pool_timeout 10_000
  @default_pool_options [
    protocols: [:http1],
    size: 100,
    count: 1,
    pool_max_idle_time: :timer.minutes(5),
    start_pool_metrics?: true
  ]

  def configure_req_defaults(config \\ config(), configure_defaults \\ &Req.default_options/1) do
    configure_defaults.(req_default_options(config))
  end

  def req_default_options(config \\ config()) do
    [
      finch: finch_name(config),
      pool_timeout: pool_timeout(config)
    ]
  end

  def finch_child_spec(config \\ config()) do
    {Finch, name: finch_name(config), pools: finch_pools(config)}
  end

  def finch_name(config \\ config()) do
    Keyword.get(config, :finch_name, @default_finch_name)
  end

  def pool_timeout(config \\ config()) do
    config
    |> Keyword.get(:pool_timeout, @default_pool_timeout)
    |> normalize_positive_integer(@default_pool_timeout)
  end

  def finch_pools(config \\ config()) do
    Keyword.get(config, :finch_pools, %{default: @default_pool_options})
  end

  defp config do
    Application.get_env(:atlas, :http, [])
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default
end
