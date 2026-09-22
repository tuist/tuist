defmodule Atlas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Atlas.Accounts.HandleRegistry
  alias Atlas.Agents.Sessions.TelemetryHandler
  alias Atlas.Engineering.Errors.DropAlerter
  alias Atlas.Engineering.Errors.Event.Buffer
  alias Atlas.Engineering.Errors.IssueAccountCoalescer
  alias Atlas.Engineering.Errors.IssueCoalescer
  alias Atlas.Engineering.Errors.KeyTouches
  alias Atlas.Engineering.Errors.SelfMonitor
  alias Atlas.HTTP
  alias Atlas.Integrations.GitHubAppBootstrap
  alias Atlas.Licenses.RateLimiter
  alias EMCP.SessionStore.ETS
  alias Guardian.DB.Sweeper

  @impl true
  def start(_type, _args) do
    attach_sentry_logger()
    TelemetryHandler.attach()
    ETS.init()
    HTTP.configure_req_defaults()

    :ok = Application.ensure_started(:logger)
    _ = Task.start(fn -> SelfMonitor.install() end)

    children =
      [
        AtlasWeb.Telemetry,
        Atlas.Vault,
        Atlas.Repo,
        HTTP.finch_child_spec(),
        {DNSCluster, query: Application.get_env(:atlas, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Atlas.PubSub},
        HandleRegistry,
        RateLimiter,
        GitHubAppBootstrap,
        {Oban, Application.fetch_env!(:atlas, Oban)},
        {Task.Supervisor, name: Atlas.TaskSupervisor},
        {Atlas.RateLimit, clean_period: :timer.minutes(10)},
        Sweeper
      ] ++
        clickhouse_children() ++
        BrowseChrome.children() ++
        [
          # Start to serve requests, typically the last entry
          AtlasWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Atlas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ClickHouse-backed Engineering.Errors pipeline. Gated on
  # `:clickhouse_enabled` so Atlas boots without ClickHouse in dev/test.
  defp clickhouse_children do
    if Application.get_env(:atlas, :clickhouse_enabled) do
      [
        Atlas.ClickHouseRepo,
        Atlas.IngestRepo,
        Supervisor.child_spec(Buffer,
          id: Buffer
        ),
        DropAlerter,
        IssueCoalescer,
        IssueAccountCoalescer,
        KeyTouches
      ]
    else
      []
    end
  end

  # Forwards Logger error/warning events to Sentry. Only attached when a
  # DSN is configured so dev/test boots stay quiet.
  defp attach_sentry_logger do
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtlasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
