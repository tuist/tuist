defmodule Tuist.Application do
  @moduledoc false

  use Application
  alias Tuist.Environment
  import Environment, only: [run_if_error_tracking_enabled: 1]

  @impl true
  def start(_type, _args) do
    Environment.decrypt_secrets() |> Environment.put_application_secrets()

    run_if_error_tracking_enabled do
      Appsignal.Phoenix.LiveView.attach()
      Appsignal.Logger.Handler.add("phoenix")
    end

    Oban.Telemetry.attach_default_logger()

    children =
      [
        TuistWeb.Telemetry,
        Tuist.Repo,
        {Oban, Application.fetch_env!(:tuist, Oban)},
        {DNSCluster, query: Application.get_env(:tuist, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Tuist.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Tuist.Finch},
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
      ] ++
        if Tuist.Environment.analytics_enabled?(),
          do: [Tuist.Analytics.Posthog, Tuist.Analytics.Attio],
          else:
            [] ++
              if(Tuist.Environment.test?(), do: [], else: [{Tuist.GitHub.Releases, []}])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tuist.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TuistWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
