defmodule Cache.Finch.Pools do
  @moduledoc false

  def config do
    server_url = Application.get_env(:cache, :server_url)

    pools = %{
      :default => [size: 10, start_pool_metrics?: true],
      server_url => [
        conn_opts: [
          log: true,
          protocols: [:http2, :http1],
          transport_opts: [
            cacertfile: CAStore.file_path(),
            verify: :verify_peer
          ]
        ],
        size: 32,
        count: 8,
        protocols: [:http2, :http1],
        start_pool_metrics?: true
      ]
    }

    case Application.fetch_env(:ex_aws, :s3) do
      {:ok, s3_config} ->
        s3_url = "#{s3_config[:scheme]}#{s3_config[:host]}"

        Map.put(pools, s3_url,
          conn_opts: [
            log: true,
            protocols: [:http2, :http1],
            transport_opts: [
              cacertfile: CAStore.file_path(),
              verify: :verify_peer
            ]
          ],
          size: 128,
          count: 8,
          protocols: [:http2, :http1],
          start_pool_metrics?: true
        )

      :error ->
        pools
    end
  end

  def urls do
    config()
    |> Map.keys()
    |> Enum.reject(&(&1 == :default))
  end
end
