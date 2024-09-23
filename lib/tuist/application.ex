defmodule Tuist.Application do
  @moduledoc false

  use Application
  alias Tuist.Environment
  import Environment, only: [run_if_error_tracking_enabled: 1]

  @impl true
  def start(_type, _args) do
    load_secrets_in_application()
    start_error_tracking()
    start_telemetry()

    application =
      Supervisor.start_link(get_children(), strategy: :one_for_one, name: Tuist.Supervisor)

    Tuist.License.assert_valid!()

    application
  end

  defp load_secrets_in_application() do
    Environment.decrypt_secrets() |> Environment.put_application_secrets()
  end

  defp start_error_tracking() do
    run_if_error_tracking_enabled do
      Appsignal.Phoenix.LiveView.attach()
      Appsignal.Logger.Handler.add("phoenix")
    end
  end

  defp start_telemetry() do
    Oban.Telemetry.attach_default_logger()
    ReqTelemetry.attach_default_logger(:pipeline)
  end

  defp get_children() do
    finch_pools =
      if Environment.test?() do
        %{:default => [size: 10]}
      else
        %{
          :default => [size: 10],
          Environment.s3_endpoint() => [
            conn_opts: [
              log: true
            ],
            size: Environment.s3_pool_size(),
            count: Environment.s3_pool_count(),
            protocols: [Environment.s3_protocol()]
          ]
        }
      end

    children =
      [
        TuistWeb.Telemetry,
        Tuist.Repo,
        {Cachex, name: :tuist},
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
        # Cache
        {Tuist.Cache.tuist(), []},
        # Start a worker by calling: Tuist.Worker.start_link(arg)
        # {Tuist.Worker, arg},
        # Start to serve requests, typically the last entry
        TuistWeb.Endpoint
      ]

    children =
      if Environment.analytics_enabled?() do
        children ++ [Tuist.Analytics.Posthog, Tuist.Analytics.Attio]
      else
        children
      end

    children
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TuistWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
