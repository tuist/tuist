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
    finch_pools =
      if Environment.test?() do
        %{:default => [size: 10]}
      else
        %{
          :default => [size: 10],
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
            protocols: Environment.s3_protocols()
          ]
        }
      end

    children =
      [
        TuistWeb.Telemetry,
        {DBConnection.TelemetryListener, name: TelemetryListener},
        {Tuist.Repo, connection_listeners: [TelemetryListener]},
        {Cachex,
         [
           :tuist,
           [
             router:
               router(
                 module: Cachex.Router.Ring,
                 options: [
                   monitor: true
                 ]
               )
           ]
         ]},
        {Oban, Application.fetch_env!(:tuist, Oban)},
        {DNSCluster, query: Application.get_env(:tuist, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Tuist.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Tuist.Finch, pools: finch_pools},
        {Guardian.DB.Sweeper, [interval: 60 * 60 * 1000]},
        # Distributed supervisor & process registry
        {
          Horde.DynamicSupervisor,
          name: Tuist.DistributedSupervisor, strategy: :one_for_one, children: []
        },
        {Tuist.API.Pipeline, []},
        # Rate limit
        {TuistWeb.RateLimit, [clean_period: 60_000 * 10]},
        # Start a worker by calling: Tuist.Worker.start_link(arg)
        # {Tuist.Worker, arg},
        # Start to serve requests, typically the last entry
        TuistWeb.Endpoint
      ]

    children
    |> Kernel.++(if Environment.analytics_enabled?(), do: [Tuist.Analytics.Posthog], else: [])
    |> Kernel.++(if Environment.redis_url(), do: [{Redix, redis_opts()}], else: [])
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
      name: :redis,
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
