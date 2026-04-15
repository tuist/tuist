defmodule TuistCommon.FinchPools do
  @moduledoc """
  Shared Finch pool configuration for services that talk to S3 via ExAws.

  `ExAws.S3.download_file/3` opens ~8 parallel GET Range requests per
  download. A small default pool wedges under concurrent processing: chunk
  `Task.async_stream` timeouts can leak in-flight connections faster than
  they're released, eventually starving new requests with "excess queuing"
  errors. This module centralizes the sizing and TLS defaults used by
  `server/`, `processor/`, and `xcode_processor/`.
  """

  @default_size 500
  @default_protocols [:http1]

  @doc """
  Builds a `{endpoint, pool_opts}` entry for Finch's `:pools` option.

  ## Options
    * `:endpoint` — required origin URL, e.g. `"https://s3.example.com"`.
    * `:size` — pool size (default `#{@default_size}`).
    * `:count` — pool count (default `System.schedulers_online()`).
    * `:protocols` — HTTP protocols (default `#{inspect(@default_protocols)}`).
    * `:use_ipv6` — boolean (default `false`).
    * `:ca_cert_pem` — PEM-encoded CA bundle. When nil, falls back to
      `CAStore.file_path/0`.
    * `:start_pool_metrics` — boolean (default `true`).
  """
  def s3_pool(opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)
    protocols = Keyword.get(opts, :protocols, @default_protocols)

    transport_opts =
      [
        inet6: Keyword.get(opts, :use_ipv6, false),
        verify: :verify_peer
      ] ++ ca_cert_opts(Keyword.get(opts, :ca_cert_pem))

    pool_opts = [
      conn_opts: [
        log: true,
        protocols: protocols,
        transport_opts: transport_opts
      ],
      size: Keyword.get(opts, :size, @default_size),
      count: Keyword.get(opts, :count, System.schedulers_online()),
      protocols: protocols,
      start_pool_metrics?: Keyword.get(opts, :start_pool_metrics, true)
    ]

    {endpoint, pool_opts}
  end

  @doc """
  Derives the S3 origin URL from the `:ex_aws, :s3` runtime config.

  Returns `nil` when the config is missing a host, so callers can skip
  installing an S3 pool in environments that don't talk to S3.
  """
  def s3_endpoint_from_ex_aws_config do
    case Application.get_env(:ex_aws, :s3) do
      nil ->
        nil

      s3_config ->
        scheme = Keyword.get(s3_config, :scheme, "https://")
        host = Keyword.get(s3_config, :host)
        port = Keyword.get(s3_config, :port)

        cond do
          is_nil(host) -> nil
          is_nil(port) -> "#{scheme}#{host}"
          true -> "#{scheme}#{host}:#{port}"
        end
    end
  end

  defp ca_cert_opts(nil), do: [cacertfile: CAStore.file_path()]

  defp ca_cert_opts(pem_content) do
    der_certs =
      pem_content
      |> :public_key.pem_decode()
      |> Enum.map(fn {_, der, _} -> der end)

    [cacerts: der_certs]
  end
end
