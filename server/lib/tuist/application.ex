defmodule Tuist.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [Tuist, TuistWeb]

  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.CommandEvents
  alias Tuist.DBConnection.TelemetryListener
  alias Tuist.Environment
  alias Tuist.QA.Logs
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Xcode.XcodeTarget

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Tuist version #{Environment.version()}")

    load_secrets_in_application()
    start_posthog()
    start_error_tracking()
    start_telemetry()

    application =
      Supervisor.start_link(get_children(), strategy: :one_for_one, name: Tuist.Supervisor)

    Logger.info("Tuist application started")

    Tuist.License.assert_valid!()

    application
  end

  defp load_secrets_in_application do
    Environment.put_application_secrets(Environment.decrypt_secrets())
  end

  defp start_posthog do
    if Environment.analytics_enabled?() do
      case Application.start(:posthog) do
        :ok ->
          Logger.info("PostHog analytics started")

        {:error, {:already_started, _}} ->
          Logger.info("PostHog analytics already started")

        {:error, reason} ->
          Logger.warning("Failed to start PostHog analytics: #{inspect(reason)}")
      end
    end
  end

  defp start_error_tracking do
    run_if_error_tracking_enabled do
      Appsignal.Phoenix.LiveView.attach()

      :logger.add_primary_filter(
        :appsignal_error_filter,
        {&TuistCommon.Appsignal.ErrorFilter.filter/2, []}
      )
    end
  end

  defp start_telemetry do
    Oban.Telemetry.attach_default_logger()
    ReqTelemetry.attach_default_logger(:pipeline)
  end

  defp get_children do
    children =
      [
        {DBConnection.TelemetryListener, name: TelemetryListener},
        {Tuist.Repo, connection_listeners: [TelemetryListener]},
        Tuist.ClickHouseRepo,
        Tuist.IngestRepo,
        Supervisor.child_spec(CommandEvents.Buffer, id: CommandEvents.Buffer),
        Supervisor.child_spec(Logs.Buffer, id: Logs.Buffer),
        Supervisor.child_spec(XcodeGraph.Buffer, id: XcodeGraph.Buffer),
        Supervisor.child_spec(XcodeProject.Buffer, id: XcodeProject.Buffer),
        Supervisor.child_spec(XcodeTarget.Buffer, id: XcodeTarget.Buffer),
        Tuist.Vault,
        {Oban, Application.fetch_env!(:tuist, Oban)},
        {Cachex, [:tuist, []]},
        {Finch, name: Tuist.Finch, pools: finch_pools()},
        {Phoenix.PubSub, name: Tuist.PubSub},
        {TuistWeb.RateLimit.InMemory, [clean_period: to_timeout(hour: 1)]},
        {Tuist.API.Pipeline, []},
        {Guardian.DB.Sweeper, [interval: 60 * 60 * 1000]},
        TuistWeb.Telemetry,
        TuistWeb.Endpoint
      ]

    children
    |> Kernel.++(
      if Environment.dev_use_remote_storage?() do
        []
      else
        %{port: minio_port, scheme: minio_scheme} = URI.parse(Environment.s3_endpoint())
        port = minio_port || 9095
        console_port = Environment.minio_console_port()

        {minio_path, 0} = System.cmd("mise", ["which", "minio"])

        minio_path = String.trim(minio_path)

        [
          {MinioServer,
           name: :minio_dev,
           port: port,
           scheme: minio_scheme,
           region: Environment.s3_region(),
           access_key_id: Environment.s3_access_key_id(),
           secret_access_key: Environment.s3_secret_access_key(),
           minio_executable: minio_path,
           console_address: ":#{console_port}"},
          Tuist.MinioBucketCreator
        ]
      end
    )
    |> Kernel.++(
      if Environment.tuist_hosted?() do
        topologies = Application.get_env(:libcluster, :topologies) || []
        [{Cluster.Supervisor, [topologies, [name: Tuist.ClusterSupervisor]]}]
      else
        []
      end
    )
    |> Kernel.++(
      if Environment.redis_url(),
        do: [
          {Redix, redis_opts()},
          {TuistWeb.RateLimit.PersistentTokenBucket, redis_opts()}
        ],
        else: []
    )
  end

  defp s3_ca_cert_opts do
    case Environment.s3_ca_cert_pem() do
      nil ->
        [cacertfile: CAStore.file_path()]

      pem_content ->
        der_certs =
          pem_content
          |> :public_key.pem_decode()
          |> Enum.map(fn {_, der, _} -> der end)

        [cacerts: der_certs]
    end
  end

  defp finch_pools do
    if Environment.test?() do
      %{:default => [size: 10]}
    else
      base_pools =
        %{
          :default => [size: 10, start_pool_metrics?: true],
          "https://api.github.com" => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 10,
            count: 2,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ],
          Environment.s3_endpoint() => [
            conn_opts: [
              log: true,
              protocols: Environment.s3_protocols(),
              transport_opts:
                [
                  inet6: Environment.use_ipv6?() in ~w(true 1),
                  verify: :verify_peer
                ] ++ s3_ca_cert_opts()
            ],
            size: Environment.s3_pool_size(),
            count: Environment.s3_pool_count(),
            protocols: Environment.s3_protocols(),
            start_pool_metrics?: true
          ],
          "https://marketing.tuist.dev" => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 10,
            count: 1,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ],
          Environment.posthog_url() => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 5,
            count: 1,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ]
        }
        |> Enum.reject(fn {key, _value} -> is_nil(key) end)
        |> Map.new()

      additional_pools =
        Map.new(Environment.additional_finch_pools(), fn {endpoint, config} ->
          {endpoint, build_additional_pool_opts(config)}
        end)

      Map.merge(base_pools, additional_pools)
    end
  end

  defp build_additional_pool_opts(config) when is_map(config) do
    size = Map.get(config, "size", 100)
    count = Map.get(config, "count", System.schedulers_online())

    [
      conn_opts: [
        log: true,
        protocols: [:http1],
        transport_opts: [
          inet6: Environment.use_ipv6?() in ~w(true 1),
          cacertfile: CAStore.file_path(),
          verify: :verify_peer
        ]
      ],
      size: size,
      count: count,
      protocols: [:http1],
      start_pool_metrics?: true
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TuistWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def redis_opts do
    %URI{} = parsed_url = URI.parse(Environment.redis_url())

    socket_opts =
      if Environment.use_ipv6?() in ~w(true 1),
        do: [:inet6, {:keepalive, true}],
        else: [{:keepalive, true}]

    opts = [
      name: Environment.redis_conn_name(),
      host: parsed_url.host,
      port: parsed_url.port,
      sync_connect: false,
      socket_opts: socket_opts
    ]

    case parsed_url.userinfo do
      nil ->
        opts

      userinfo ->
        auth_opts =
          case String.split(userinfo, ":", parts: 2) do
            [username] -> [username: username]
            [username, password] -> [username: username, password: password]
            _ -> []
          end

        Keyword.merge(opts, auth_opts)
    end
  end
end
