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

        {_s3_url, s3_pool_opts} =
          TuistCommon.FinchPools.s3_pool(
            endpoint: s3_url,
            size: 128,
            count: 8,
            protocols: s3_protocols,
            ca_cert_pem: Cache.Config.s3_ca_cert_pem()
          )

        s3_url
        |> s3_endpoints()
        |> Enum.reduce(pools, fn endpoint, acc -> Map.put(acc, endpoint, s3_pool_opts) end)

      :error ->
        pools
    end
  end

  def urls do
    config()
    |> Map.keys()
    |> Enum.reject(&(&1 == :default))
  end

  defp s3_endpoints(s3_url) do
    Enum.uniq([s3_url | virtual_host_s3_endpoints(s3_url)])
  end

  defp virtual_host_s3_endpoints(s3_url) do
    if Cache.Config.s3_virtual_host() do
      [
        Cache.Config.cache_bucket(),
        Cache.Config.xcode_cache_bucket() || Cache.Config.cache_bucket(),
        Cache.Config.registry_bucket()
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&bucket_endpoint(s3_url, &1))
    else
      []
    end
  end

  defp bucket_endpoint(s3_url, bucket) do
    s3_url
    |> URI.parse()
    |> Map.update!(:host, fn host -> "#{bucket}.#{host}" end)
    |> URI.to_string()
  end
end
