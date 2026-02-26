defmodule Cache.Finch.Pools do
  @moduledoc false

  def config do
    server_url = Cache.Config.server_url()
    s3_protocols = Cache.Config.s3_protocols()

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

    case Cache.Config.s3_config() do
      {:ok, s3_config} ->
        s3_url =
          case s3_config[:port] do
            nil -> "#{s3_config[:scheme]}#{s3_config[:host]}"
            port -> "#{s3_config[:scheme]}#{s3_config[:host]}:#{port}"
          end

        Map.put(pools, s3_url,
          conn_opts: [
            log: true,
            protocols: s3_protocols,
            transport_opts: [
              cacertfile: CAStore.file_path(),
              verify: :verify_peer
            ]
          ],
          size: 128,
          count: 8,
          protocols: s3_protocols,
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
