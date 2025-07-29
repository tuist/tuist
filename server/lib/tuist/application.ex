defmodule Tuist.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [Tuist, TuistWeb]

  import Cachex.Spec
  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.DBConnection.TelemetryListener
  alias Tuist.Environment

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Tuist version #{Environment.version()}")

    load_secrets_in_application()
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

  defp start_error_tracking do
    run_if_error_tracking_enabled do
      Appsignal.Phoenix.LiveView.attach()
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
        {Oban, Application.fetch_env!(:tuist, Oban)},
        {Cachex, [:tuist, cachex_opts()]},
        {Finch, name: Tuist.Finch, pools: finch_pools()},
        {Phoenix.PubSub, name: Tuist.PubSub},
        TuistWeb.Telemetry
      ]

    children
    |> Kernel.++(
      if Environment.web?(),
        do: [
          {TuistWeb.RateLimit.InMemory, [clean_period: to_timeout(hour: 1)]},
          {Tuist.API.Pipeline, []},
          TuistWeb.Endpoint
        ],
        else: []
    )
    |> Kernel.++(
      if Environment.worker?(),
        do: [
          {Guardian.DB.Sweeper, [interval: 60 * 60 * 1000]}
        ],
        else: []
    )
    |> Kernel.++(if Environment.analytics_enabled?(), do: [Tuist.Analytics.Posthog], else: [])
    |> Kernel.++(
      if Environment.tuist_hosted?(),
        do: [{DNSCluster, query: Application.get_env(:tuist, :dns_cluster_query) || :ignore}],
        else: []
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

  def cachex_opts do
    if Environment.tuist_hosted?() do
      # Tuist-managed instances are configured to support a multi-node cluster.
      [
        router:
          router(
            module: Cachex.Router.Ring,
            options: [
              monitor: true
            ]
          )
      ]
    else
      # In on-premise environments we assume a single Node.
      []
    end
  end

  defp finch_pools do
    if Environment.test?() do
      %{:default => [size: 10]}
    else
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
          count: 1,
          protocols: [:http2, :http1],
          start_pool_metrics?: true
        ],
        Environment.s3_endpoint() => [
          conn_opts: [
            log: true,
            protocols: Environment.s3_protocols(),
            transport_opts: [
              inet6: Environment.use_ipv6?() in ~w(true 1),
              cacertfile: CAStore.file_path(),
              verify: :verify_peer
            ]
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
        ]
      }
    end
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
